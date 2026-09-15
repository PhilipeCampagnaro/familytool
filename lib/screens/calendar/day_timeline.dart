part of '../calendar_screen.dart';

// =============================================================================
// The day as a time grid
//
// **The day view is a clock, not a list.** It was a rail of rounded cards in
// reading order, which said what was on but never what the day *looked* like: a
// morning packed solid and a free afternoon drew as six identical rows. A grid
// is the shape every calendar the household already uses has — Apple's, Google's
// Outlook's, Teams' — so the one thing nobody has to learn here is how to read
// it.
//
// What that costs is the card: a 30-minute block is about 34 points tall and
// holds a title and nothing else, so the weather, the calendar chip and the
// linked-list markers moved to the detail sheet behind the tap. That is the
// trade a grid makes and it is worth making — the position *is* the
// information now. What a block does have room for it stacks full width, in
// reading order, and cuts to what fits: see [_EventBlock._detailLines].
// =============================================================================

/// One thing standing on the day's clock, clipped to the day being drawn.
///
/// Minutes from that day's midnight rather than [DateTime]s, because every
/// question the layout asks is "does this overlap that" and "how far down does
/// it sit" — and an overnight shift or a Ferien block is one appointment across
/// two dates, each of which draws only its own share. Without the clip a
/// 22:00–07:00 event runs off the bottom of Monday and never appears on Tuesday
/// at all.
class _TimedEntry {
  /// A [CalendarEvent] or a [BoardTask] — the block tells them apart.
  final Object entry;

  /// Minutes from midnight, 0–1440.
  final int from;
  final int to;

  /// [to] pushed out to at least [_minSlotMinutes].
  ///
  /// Used for the height **and** the overlap test, so a five-minute reminder is
  /// a block that can be read and hit rather than a coloured hairline — and so
  /// two of them at one moment still lay out side by side instead of collapsing
  /// onto each other.
  final int slotTo;

  const _TimedEntry({required this.entry, required this.from, required this.to, required this.slotTo});

  bool overlaps(_TimedEntry other) => other.from < slotTo && from < other.slotTo;
}

/// Where one entry ends up on the grid: which column, out of how many, and how
/// many of them it is allowed to spread across.
class _PlacedBlock {
  final _TimedEntry entry;
  final int column;
  final int columns;

  /// How many columns wide. **This is the half that makes a grid readable**:
  /// an 11:00 half-hour meeting in a day whose 09:00–17:00 workday forced two
  /// columns has no reason to be half a screen wide, so it spreads into every
  /// column to its right that nothing overlapping occupies.
  final int span;

  const _PlacedBlock({required this.entry, required this.column, required this.columns, required this.span});
}

/// The shortest an appointment is drawn and laid out as. Apple rounds a
/// zero-length event up much the same way; without it a provider row with
/// `start == end` is invisible and un-tappable.
const _minSlotMinutes = 20;

/// Lays a day's appointments out in columns, the way every calendar that has
/// ever solved this does it.
///
/// Three steps, and the third is the one people leave out:
///
/// 1. **Collision groups.** Walking the day in start order, an entry joins the
///    group while it begins before the group's furthest end so far. Two groups
///    never interact, so each is solved on its own and a quiet afternoon is not
///    made narrow by a crowded morning.
/// 2. **Greedy columns.** Inside a group, an entry takes the first column whose
///    last entry has already finished; otherwise it opens a new one. Entries are
///    in start order, so a column's last entry is always its latest-ending one
///    and that check is exact rather than approximate.
/// 3. **Spread right.** Each entry then widens into the columns to its right
///    until it meets something it overlaps. Without this the layout is correct
///    and unreadable: every block in a group is 1/n wide even when nothing is
///    beside it.
///
/// Deliberately **not** Apple's own behaviour, which is undocumented and which
/// its own users describe as arbitrary — sometimes side by side, sometimes
/// shingled on top of one another. This is the deterministic version Google
/// Calendar, Outlook and Teams all draw: no two blocks ever cover each other,
/// and the same day always lays out the same way.
List<_PlacedBlock> _placeBlocks(List<_TimedEntry> entries) {
  if (entries.isEmpty) return const [];

  final sorted = [...entries]..sort((a, b) {
    final byStart = a.from.compareTo(b.from);
    // Longest first among equal starts, so the appointment that shapes the
    // group takes the leftmost column and the short ones fill in beside it.
    return byStart != 0 ? byStart : b.slotTo.compareTo(a.slotTo);
  });

  final out = <_PlacedBlock>[];
  var group = <_TimedEntry>[];
  var groupEnd = -1;

  void flush() {
    if (group.isEmpty) return;
    out.addAll(_packGroup(group));
    group = [];
    groupEnd = -1;
  }

  for (final entry in sorted) {
    if (group.isNotEmpty && entry.from >= groupEnd) flush();
    group.add(entry);
    groupEnd = math.max(groupEnd, entry.slotTo);
  }
  flush();
  return out;
}

List<_PlacedBlock> _packGroup(List<_TimedEntry> group) {
  final columns = <List<_TimedEntry>>[];
  final columnOf = <_TimedEntry, int>{};

  for (final entry in group) {
    var placed = false;
    for (var c = 0; c < columns.length; c++) {
      if (columns[c].last.slotTo <= entry.from) {
        columns[c].add(entry);
        columnOf[entry] = c;
        placed = true;
        break;
      }
    }
    if (!placed) {
      columns.add([entry]);
      columnOf[entry] = columns.length - 1;
    }
  }

  return [
    for (final entry in group)
      _PlacedBlock(
        entry: entry,
        column: columnOf[entry]!,
        columns: columns.length,
        span: _spanRight(entry, columnOf[entry]!, columns),
      ),
  ];
}

int _spanRight(_TimedEntry entry, int column, List<List<_TimedEntry>> columns) {
  var span = 1;
  for (var c = column + 1; c < columns.length; c++) {
    if (columns[c].any(entry.overlaps)) break;
    span++;
  }
  return span;
}

/// Which hours the grid draws.
///
/// **Not all twenty-four.** Apple shows the whole day and scrolls it, which
/// works when the day view *is* the screen; here it sits under a collapsing day
/// strip inside a page that already scrolls, and a household opening the app
/// would be looking at four empty hours before breakfast. So the grid covers
/// what the day actually uses, an hour of air either side, and never less than
/// [_minWindowHours] so that a single appointment still reads as a calendar
/// rather than as one box.
///
/// Today's own hour is always inside it, or the "now" line would point at a
/// strip that isn't drawn.
({int from, int to}) _dayWindow(List<_TimedEntry> timed, DateTime day) {
  var from = 8;
  var to = 20;

  if (timed.isNotEmpty) {
    from = 24;
    to = 0;
    for (final e in timed) {
      from = math.min(from, e.from ~/ 60);
      to = math.max(to, (e.slotTo / 60).ceil());
    }
    from = math.max(0, from - 1);
    to = math.min(24, to + 1);
  }

  if (_isToday(day.year, day.month, day.day)) {
    final now = DateTime.now();
    from = math.min(from, math.max(0, now.hour - 1));
    to = math.max(to, math.min(24, now.hour + 2));
  }

  while (to - from < _minWindowHours) {
    if (to < 24) {
      to++;
    } else if (from > 0) {
      from--;
    } else {
      break;
    }
  }
  return (from: from, to: to);
}

const _minWindowHours = 6;

/// The whole day: the band of things that are true of it, then the clock.
class _DayTimeline extends StatelessWidget {
  final _DayPlan plan;

  /// Drawn as the first chip in the band — a Feiertag is a property of the date
  /// and belongs with the other things true of the whole day, not in a row of
  /// its own above them at a different size.
  final GermanHoliday? holiday;

  final DateTime day;
  final String headingText;
  final Color accent;
  final bool compact;

  const _DayTimeline({
    required this.plan,
    required this.holiday,
    required this.day,
    required this.headingText,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final window = _dayWindow(plan.timed, day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (holiday != null || plan.allDay.isNotEmpty || plan.untimedTodos.isNotEmpty)
          _DayBand(
            plan: plan,
            holiday: holiday,
            day: day,
            headingText: headingText,
            accent: accent,
            compact: compact,
            divided: plan.timed.isNotEmpty,
          ),
        if (plan.timed.isNotEmpty)
          _HourGrid(
            // Replays the blocks' entrance when the day changes, which is the
            // animation the reader is actually watching — the day panel's own
            // size change carries the rest.
            key: ValueKey('${day.year}-${day.month}-${day.day}'),
            blocks: _placeBlocks(plan.timed),
            fromHour: window.from,
            toHour: window.to,
            day: day,
            headingText: headingText,
            accent: accent,
            compact: compact,
          ),
      ],
    );
  }
}

/// The hour rules, the blocks standing on them, and the line where the day has
/// got to.
class _HourGrid extends ConsumerStatefulWidget {
  final List<_PlacedBlock> blocks;
  final int fromHour;
  final int toHour;
  final DateTime day;
  final String headingText;
  final Color accent;
  final bool compact;

  const _HourGrid({
    super.key,
    required this.blocks,
    required this.fromHour,
    required this.toHour,
    required this.day,
    required this.headingText,
    required this.accent,
    required this.compact,
  });

  @override
  ConsumerState<_HourGrid> createState() => _HourGridState();
}

class _HourGridState extends ConsumerState<_HourGrid> with SingleTickerProviderStateMixin {
  /// One hour of the day, in points. A 30-minute appointment is half of it,
  /// which is the shortest block that still holds a title on one line beside
  /// its duration.
  static const _hourHeight = 68.0;
  static const _hourHeightCompact = 58.0;

  /// Between two blocks standing side by side.
  static const _blockGap = 4.0;

  /// How many rows of dots make an hour. Four, so the lattice marks the quarter
  /// hour — fine enough to read as a canvas, coarse enough that the hour's own
  /// row is still obviously the strong one.
  static const _rowsPerHour = 4;

  /// How far the lattice keeps going past the grid, so it reaches the grey
  /// card's own edges above the all-day band and below the last hour.
  ///
  /// Comfortably more than anything that stands between the grid and the card's
  /// edge — the heading and a band of chips come to about a hundred points, the
  /// card's own padding to twenty — rather than measured from them, because a
  /// canvas that has to be told the height of the heading above it goes wrong
  /// the day somebody adds a chip. Not *arbitrarily* more, though: every point
  /// of it is rows and columns computed on each paint, and the card throws them
  /// away. See [_DotCanvas.bleed].
  static const _dotBleed = 240.0;

  late final AnimationController _entrance = AnimationController(
    duration: const Duration(milliseconds: 460),
    vsync: this,
  )..forward();

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  double get _hour => widget.compact ? _hourHeightCompact : _hourHeight;

  /// Each block arrives a beat after the one before it, so the day assembles
  /// down the page rather than appearing whole. Capped, or a crowded day would
  /// still be arriving after half a second.
  double _stagger(double t, int i, int n) {
    final step = n <= 1 ? 0.0 : math.min(0.5 / (n - 1), 0.06);
    final begin = math.min(i * step, 0.55);
    return Curves.easeOutCubic.transform(((t - begin) / (1 - begin)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final hours = widget.toHour - widget.fromHour;
    final originMinutes = widget.fromHour * 60;
    // Only the clock, not the whole calendar: this rebuilds every thirty
    // seconds to move the "now" line, and a grid of blocks has no reason to be
    // rebuilt with it.
    final now = ref.watch(calendarProvider.select((s) => s.now));
    final isToday = _isToday(widget.day.year, widget.day.month, widget.day.day);
    final nowMinutes = now.hour * 60 + now.minute;
    final showNow = isToday && nowMinutes >= originMinutes && nowMinutes <= widget.toHour * 60;

    return SizedBox(
      height: hours * _hour,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackLeft = _gutter + _gutterGap;
          final trackWidth = math.max(0.0, constraints.maxWidth - trackLeft);

          double y(int minutes) => (minutes - originMinutes) / 60 * _hour;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // **The lattice runs the full width, gutter included, and past
              // the grid in every direction to the card's own edges.** Stopping
              // it where the blocks start drew a second left edge a finger in
              // from the card's own, and stopping it at the first and last hour
              // drew two more — which is the thing a canvas is not supposed to
              // have: a surface with a scale runs under everything standing on
              // it, labels and chips as much as appointments. `_DayBody` clips
              // the overdraw at the card's corner; see [_DotCanvas.bleed].
              Positioned.fill(
                child: CustomPaint(
                  painter: _DotCanvas(
                    step: _hour / _rowsPerHour,
                    rowsPerHour: _rowsPerHour,
                    hourDot: AppColors.hairline2,
                    dot: AppColors.hairline2.withValues(alpha: 0.45),
                    bleed: _dotBleed,
                  ),
                ),
              ),
              // The last hour's label is skipped: the grid closes on that line
              // and naming it would put an hour on the page the day does not
              // cover.
              for (var i = 0; i < hours; i++)
                _HourLabel(top: i * _hour, label: _hourLabel(widget.fromHour + i), gutter: _gutter),
              for (var i = 0; i < widget.blocks.length; i++)
                Builder(builder: (context) {
                  final placed = widget.blocks[i];
                  final column = trackWidth / placed.columns;
                  final top = y(placed.entry.from);
                  final height = math.max(_minBlockHeight, y(placed.entry.slotTo) - top);
                  return Positioned(
                    top: top,
                    left: trackLeft + placed.column * column,
                    width: math.max(0.0, column * placed.span - _blockGap),
                    height: height,
                    child: AnimatedBuilder(
                      animation: _entrance,
                      builder: (context, child) {
                        final t = _stagger(_entrance.value, i, widget.blocks.length);
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
                        );
                      },
                      child: _DayBlock(
                        entry: placed.entry,
                        headingText: widget.headingText,
                        accent: widget.accent,
                        now: now,
                        height: height,
                        width: math.max(0.0, column * placed.span - _blockGap),
                      ),
                    ),
                  );
                }),
              if (showNow)
                Positioned(
                  top: y(nowMinutes) - 4,
                  left: _gutter - 2,
                  right: 0,
                  child: _NowLine(accent: widget.accent),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The hour labels' column, and the gap to the blocks — **and the all-day
/// band's**, which is why they live out here rather than on the grid.
///
/// **Sized to the widest label and not a point more.** It was 42, which is
/// what a gutter needs if it is going to hold "Ganztägig"; the band took that
/// word away and the number stayed behind, so nine points of every block's
/// width were being spent on empty gutter. 34 fits "12 PM" — wider than
/// "12:00" — at [AppText.microLabel], and the label shrinks rather than clips
/// past that.
///
/// The labels stay **right-aligned**, hugging the rules the way every calendar
/// draws them. That also happens to be what lands them on the screen title's
/// own left edge: right-aligned in 34 from the card's 14, "15:00" starts at
/// about 24, which is exactly where the title starts.
///
/// The band above the clock keeps the same column: the day's page mark stands
/// where an hour label would, so the all-day chips start on the blocks' own
/// left edge rather than a gutter's width to the left of them.
const _gutter = 34.0;
const _gutterGap = 7.0;

/// The stripe down a block's left edge — a timeline block's and an all-day
/// chip's alike. See [_EventBlock].
const _accentBar = 3.0;

/// Nothing shorter than this, however short the appointment. A 10-minute block
/// at 68 points an hour is 11 points tall, which is neither readable nor a tap
/// target — and [_minSlotMinutes] already keeps the *layout* honest about it.
const _minBlockHeight = 32.0;

/// "10:00" or "10 AM" — the hour on its own, which is what a grid rule wants.
/// [formatTimeOfDay] would print "10:00 AM", and the minutes are noise on a line
/// that is by definition on the hour.
String _hourLabel(int hour) {
  if (L.s.use24HourClock) return '${hour.toString().padLeft(2, '0')}:00';
  final suffix = hour < 12 ? 'AM' : 'PM';
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h $suffix';
}

/// The lattice the day stands on.
///
/// **Dots rather than rules, and the difference is what the eye does with
/// them.** A full-width hairline every hour drew twelve horizontal lines across
/// the day and each one asked to be read; the appointments then had to compete
/// with the paper they were printed on. A dot grid is the canvas every tool that
/// puts objects on a plane uses — Figma, Power Automate, n8n — precisely because
/// it says "this is a surface with a scale" and then gets out of the way.
///
/// It runs the **full width of the timeline**, under the hour labels as much as
/// under the blocks. Stopping it where the blocks start drew a second left edge
/// a finger in from the card's own, which is exactly what a canvas is not
/// supposed to have.
///
/// It is still a *calendar's* lattice, not decoration: the rows land on the
/// quarter hour ([_rowsPerHour]) and the hour's own row is drawn at full
/// strength while the three between it are faded, so the hour is findable
/// without a line being drawn through the day to find it. The lattice is square
/// — the columns are spaced at the same [step] as the rows — which is what keeps
/// it reading as a canvas rather than as a dashed rule.
///
/// One painter for the whole grid and one [Canvas.drawPoints] per strength, so
/// a day covering fourteen hours costs two draw calls rather than six hundred
/// widgets.
class _DotCanvas extends CustomPainter {
  /// Distance between two dots, in both axes.
  final double step;

  /// How many rows make an hour — which row gets [hourDot] rather than [dot].
  final int rowsPerHour;

  final Color dot;
  final Color hourDot;

  /// How far past its own bounds the lattice keeps going, in points.
  ///
  /// **The painter is sized by the hour grid and clipped by the grey card**,
  /// which is the only arrangement that gets both halves right. The lattice has
  /// to be *phased* on the grid, because an hour's row is drawn at full strength
  /// and the three between it faded — that is what makes an hour findable
  /// without a line through the day — and the grid is the only thing that knows
  /// where an hour is. But it has to *reach* the card's own edges, above the
  /// band of all-day chips and below the last hour, or the dots stop halfway up
  /// a grey panel and read as a texture somebody forgot to finish.
  ///
  /// So it overdraws in every direction and `_DayBody` cuts it at the card's
  /// rounded corner. Generous rather than measured: a canvas that has to be told
  /// the height of the heading above it is a canvas that goes wrong the day
  /// somebody adds a chip.
  final double bleed;

  const _DotCanvas({
    required this.step,
    required this.rowsPerHour,
    required this.dot,
    required this.hourDot,
    required this.bleed,
  });

  /// The dot itself, as a round stroke cap. Big enough to survive a dark
  /// palette, small enough that a block laid over it hides it completely.
  static const _size = 1.7;
  static const _hourSize = 2.1;

  @override
  void paint(Canvas canvas, Size size) {
    if (step <= 0 || size.width <= 0) return;
    final minor = <Offset>[];
    final major = <Offset>[];

    // Whole steps out, so the lattice keeps its phase on the way past the edge
    // — and Dart's `%` answers non-negative for a positive divisor, so a row at
    // -4 is an hour row exactly as row 4 is.
    final out = (bleed / step).ceil();
    final firstColumn = -out;
    final lastColumn = ((size.width + bleed) / step).ceil();

    for (var row = -out; row * step <= size.height + bleed; row++) {
      final y = row * step;
      final target = row % rowsPerHour == 0 ? major : minor;
      for (var column = firstColumn; column <= lastColumn; column++) {
        target.add(Offset(column * step, y));
      }
    }

    canvas.drawPoints(
      PointMode.points,
      minor,
      Paint()
        ..color = dot
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _size,
    );
    canvas.drawPoints(
      PointMode.points,
      major,
      Paint()
        ..color = hourDot
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _hourSize,
    );
  }

  @override
  bool shouldRepaint(_DotCanvas old) =>
      old.step != step ||
      old.rowsPerHour != rowsPerHour ||
      old.dot != dot ||
      old.hourDot != hourDot ||
      old.bleed != bleed;
}

/// The hour, named in the gutter. The lattice beside it is [_DotCanvas]; this
/// draws no line of its own.
class _HourLabel extends StatelessWidget {
  final double top;
  final String label;
  final double gutter;

  const _HourLabel({required this.top, required this.label, required this.gutter});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top - _height / 2,
      left: 0,
      width: gutter,
      height: _height,
      child: Align(
        alignment: Alignment.centerRight,
        // Shrinks rather than clips: the gutter is sized for the widest label at
        // the shipped text scale, and an accessibility scale makes every label
        // wider than that. The rail this replaced used the same treatment for
        // the same reason.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            label,
            textAlign: TextAlign.right,
            maxLines: 1,
            softWrap: false,
            style: AppText.microLabel.copyWith(color: AppColors.muted, letterSpacing: -0.1),
          ),
        ),
      ),
    );
  }

  /// Enough for the label at any text scale it can shrink into, and centred on
  /// the hour's own row of dots.
  static const _height = 16.0;
}

/// Where the day has got to — a dot on the gutter's edge and a line across the
/// hours.
///
/// It replaces what the old rail said with its filled dots and accent line, and
/// says it in one mark instead of one per appointment.
class _NowLine extends StatelessWidget {
  final Color accent;

  const _NowLine({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
        Expanded(child: Container(height: 1.5, color: accent)),
      ],
    );
  }
}

/// A calendar's colour, pushed to a lightness that reads as ink on its own
/// tinted fill.
///
/// **The block carries the calendar, so the calendar chip is gone** — a dot
/// beside a name saying "Familie" on a block already painted in Familie's
/// colour was saying it twice, and cost a chip's width to do it. That only works
/// if the colour survives being text: a provider hands over whatever the account
/// picked, including pale yellows that vanish on a pale yellow ground, so the
/// hue is kept and the lightness is clamped rather than trusted.
Color _blockInk(Color c) {
  final hsl = HSLColor.fromColor(c);
  return AppColors.isDark
      ? hsl.withLightness(hsl.lightness.clamp(0.68, 0.86)).withSaturation(math.min(hsl.saturation, 0.7)).toColor()
      : hsl.withLightness(math.min(hsl.lightness, _inkLightness)).toColor();
}

/// How dark the title goes on a light palette. **A ceiling, not a target**: a
/// calendar already darker than this keeps its own colour, so only the pale ones
/// are pushed.
///
/// Deep enough to read as ink and still plainly the calendar's hue — the point
/// of colouring the type at all is that a block says which calendar it belongs
/// to twice, in the fill and in the text, so this must not slide to black. The
/// saturation is untouched for the same reason, which is also what keeps it
/// moving *with* [_fillLightness]: both are the same hue, so darkening the type
/// buys contrast against the chip rather than spending the colour.
const _inkLightness = 0.26;

/// The block's own material — **the same flat tint every chip in the app
/// wears**, in the calendar's colour instead of the accent.
///
/// [_HolidayChip] is the pattern and this is the whole of it: `tint(colour,
/// .86)`, nothing around it, the colour itself carrying the text. Three richer
/// treatments were tried and each was louder than what it was holding — a
/// coloured outline at a full point and again at a tenth of one, which put a
/// line around every hour of the day; a translucent fill, which could not keep a
/// shadow, because a shadow paints behind the box and a chip you can see through
/// is a chip you see the shadow through; and the shadow on its own, which lifted
/// twenty chips off a card that is the background rather than a surface.
///
/// **The cost is named rather than designed around**: a calendar whose account
/// gave it a grey — iCloud does, for "Familie" — is a pale grey chip on a grey
/// card, and nothing is left to rescue it. The household picking its own colour
/// is what fixes that, and it is queued as 2d in the production plan.
BoxDecoration _blockChip(Color c, {double radius = 10}) => BoxDecoration(
      color: _blockFill(c),
      borderRadius: BorderRadius.circular(radius),
    );

/// A to-do's chip: **outlined where an appointment is filled.**
///
/// It was `surfaceAlt`, and both day cards are `screenBg` — two greys a
/// percent apart, so the to-do was a label floating on nothing. The card's own
/// `surface` lifts it off the grey, and the rim is the check-off's idle ring
/// colour, so the outline and the circle at its end read as one object. Filled
/// means "a calendar's", outlined means "the Board's" — the shape carries the
/// difference the colour no longer has to.
BoxDecoration _todoChip({double radius = 10}) => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.idleRing, width: 1),
    );

/// The chip's fill: the calendar's colour lightened, **not mixed with white**.
///
/// This is the whole difference between a vivid chip and a beige one. [tint]
/// lerps toward white, which raises lightness *and* drags saturation to zero —
/// a blue at 86% of the way to white is a grey-blue, and a day of them reads as
/// a set of envelopes. Moving the colour up the lightness axis in HSL instead
/// keeps the hue at full strength and every calendar distinguishable from the
/// next.
///
/// **Opaque, and that is what lets the day keep its grey card.** An alpha of the
/// colour was the other way to stay vivid, and it takes whatever is behind it
/// into its own colour: over grey every calendar drifted toward one dusty
/// register, which is exactly the problem this is solving. Opaque means the chip
/// looks the same whatever it stands on.
///
/// Saturation is **scaled, never floored**. A small boost makes a colour that
/// has a hue read more strongly; a floor would invent one for a calendar that
/// has none, and the app does not pick colours on a household's behalf — iCloud
/// calls "Familie" a grey and a grey it stays, until somebody changes it in the
/// calendar's own sheet.
Color _blockFill(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withSaturation((hsl.saturation * _fillSaturation).clamp(0.0, 1.0))
      .withLightness(AppColors.isDark ? _fillLightnessDark : _fillLightness)
      .toColor();
}

/// Where the chip sits on the lightness axis. **The one dial**: down is more
/// vivid, up is more paper.
///
/// The ceiling is the text rather than taste — [_blockInk] draws the title in
/// the same hue clamped dark, so the chip and its own label close on each other
/// as this falls. This is near that limit, and the title is deliberately not
/// darkened to buy room: that trades the colour of the type for the colour of
/// the chip, and on a day of eight appointments the type is what you are
/// actually reading.
const _fillLightness = 0.88;

/// The same distance from a dark ground that [_fillLightness] is from a light
/// one. A chip as pale on a dark card as it is on a light one reads as a hole
/// punched in the card rather than as an appointment.
const _fillLightnessDark = 0.24;

/// A modest lift, applied to the saturation the calendar already has.
const _fillSaturation = 1.15;

/// A chip's shape when the thing it holds has no height of its own — the all-day
/// band, where a row really is a chip. A block standing on the clock keeps a
/// modest radius instead: a capsule as tall as an afternoon is a lozenge, and
/// its corners eat the title.
const _chipRadius = 999.0;

/// One appointment or timed to-do, standing on the grid.
class _DayBlock extends StatelessWidget {
  final _TimedEntry entry;
  final String headingText;
  final Color accent;
  final DateTime now;

  /// What the grid gave it, so the block can lay itself out for the room it has
  /// rather than guess. The height is the clock's answer and the width is the
  /// overlap layout's.
  final double height;
  final double width;

  const _DayBlock({required this.entry, required this.headingText, required this.accent, required this.now, required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    if (entry.entry case final BoardTask task) {
      return _TodoBlock(task: task, accent: accent, height: height);
    }
    return _EventBlock(
      event: entry.entry as CalendarEvent,
      headingText: headingText,
      now: now,
      height: height,
      width: width,
    );
  }
}

/// An appointment as a coloured block.
///
/// **Two chips came off it and neither is missed.** The duration chip is now the
/// grey figure on the right, because a block's *height* already says how long it
/// runs and the figure is there to name it exactly; the calendar chip is the
/// fill. The weather and the linked-list markers went to the detail sheet — a
/// half-hour block is 34 points tall and a forecast icon alone is 26 of them.
class _EventBlock extends ConsumerWidget {
  final CalendarEvent event;
  final String headingText;
  final DateTime now;
  final double height;
  final double width;

  const _EventBlock({required this.event, required this.headingText, required this.now, required this.height, required this.width});

  /// Below this the block's padding tightens, which is the only thing height
  /// decides directly — how many lines it holds is worked out in [_detailLines].
  static const _tight = 48.0;

  /// What the block says under its title, in the order a household reads it, cut
  /// to the lines that actually fit.
  ///
  /// **The duration came off the title's row and went to the bottom of the
  /// stack.** Pinned top-right it competed with the name for the one line every
  /// block has; down here it is the last thing to arrive and the first to go,
  /// which is right — a block's *height* is already the duration, and the figure
  /// only names it exactly. A half-hour appointment is therefore its title and
  /// nothing else, which is all a half-hour appointment has room to be.
  ///
  /// Measured against the room the clock gave the block rather than against a
  /// list of height thresholds: one number changing ([_HourGridState._hourHeight],
  /// the padding, a text scale) must not leave four `if`s disagreeing about what
  /// fits. The scale is read from the context for the same reason — lines are
  /// taller for a household that asked for larger type, and fewer of them fit.
  static List<String> _detailLines(
    BuildContext context,
    CalendarEvent event,
    double height,
    double width,
    double pad,
    double reserve,
    double beside,
  ) {
    final lines = <String>[
      if (event.body.trim().isNotEmpty) event.body.trim(),
      if (event.loc.trim().isNotEmpty) event.loc.trim(),
      // **"16:00 – 17:30 Uhr" where the block is wide enough to say it, and
      // "1 Std 30" where it is not.** A block only gets narrow because something
      // else starts inside it, and the one thing a reader needs at that moment
      // is which of the two is which — not two clock times fighting an ellipsis
      // in half a column. The range is the better label whenever it fits, since
      // the block's *position* already gives the start and only its end has to
      // be read off the height.
      width >= _rangeWidth ? event.timeRangeLabel : event.durationLabel,
    ];

    final scale = MediaQuery.textScalerOf(context);
    // Measured without the repeat mark in the title, because the mark is only
    // *in* the title on a block where no line fits at all — so an answer of one
    // line or more makes this assumption true, and an answer of none makes it
    // irrelevant. No circle, and no repeating appointment paying for room it is
    // not using.
    final room = height - pad * 2 - _titleRow(context, beside) - reserve;
    final fits = (room / scale.scale(_detailLine)).floor().clamp(0, lines.length);
    return lines.take(fits).toList();
  }

  /// The height of the title's own row.
  ///
  /// **The mark beside the title is taller than the title**, and it does not
  /// scale — it is a drawing. So the row is whichever wins, which at a large
  /// accessibility scale is the text again, exactly as it should be. Only the
  /// *first* line is this tall; a title that wraps adds plain [_titleLine]s
  /// under it.
  static double _titleRow(BuildContext context, double beside) => math.max(
        MediaQuery.textScalerOf(context).scale(_titleLine),
        beside,
      );

  /// How many lines the name may wrap onto.
  ///
  /// **The leftovers, and only the leftovers.** [_detailLines] runs first on a
  /// one-line title, because where the appointment is and when it ends are
  /// facts that a name's third line is not — a block too small for both should
  /// spend its second line on the place rather than on the rest of the title.
  /// Whatever height is *still* unspent after that comes back to the title.
  ///
  /// On a half-hour block there is nothing left and the name ellipses as it
  /// always did. On a four-hour block it is most of the block, and a name that
  /// used to stop at "Festakt 50 Ja…" over four centimetres of empty green
  /// gets to finish saying itself.
  static int _titleLines(
    BuildContext context,
    double height,
    double pad,
    int drawn,
    double reserve,
    double beside,
  ) {
    final scale = MediaQuery.textScalerOf(context);
    final spare =
        height - pad * 2 - _titleRow(context, beside) - reserve - drawn * scale.scale(_detailLine);
    final extra = spare <= 0 ? 0 : spare ~/ scale.scale(_titleLine);
    return (1 + extra).clamp(1, _maxTitleLines);
  }

  /// **Three, and the rest of a tall block stays empty.** Past a third line a
  /// name is a paragraph rather than something read at a glance, and no real
  /// appointment title needs a fourth at this size. Air below a long
  /// appointment is not wasted space — it *is* the appointment being long,
  /// which is the one thing the grid says better than any label.
  static const _maxTitleLines = 3;

  /// The title's line and one detail line at the shipped text scale. Used only
  /// to decide *how many* lines to draw — the lines themselves are laid out by
  /// Flutter, so being a point out here costs a line at a boundary and never a
  /// clipped one.
  static const _titleLine = 18.0;
  static const _detailLine = 16.0;

  /// Enough for "16:00 – 17:30 Uhr" at [AppText.microLabel] with the block's
  /// padding around it. Below this the duration goes in instead.
  static const _rangeWidth = 168.0;

  /// A block at least this wide spells its link badges out — "1 Liste" beside
  /// the glyph; under it the glyph stands alone. An appointment carrying both a
  /// list and a to-do asks for [_badgeLabelStep] more before either is spelled
  /// out, because two half-labels is the one outcome worth avoiding.
  ///
  /// Measured the same way [_rangeWidth] is, and for the same reason: the badge
  /// shares a line with the time, so what decides its form is the room left
  /// over on that line rather than anything about the block's height.
  static const _badgeLabelWidth = 196.0;
  static const _badgeLabelStep = 74.0;

  /// Under this the forecast comes off the block entirely. It is the one mark
  /// down there that is decoration rather than fact — the list, the to-do and
  /// the repeat all say something about the appointment itself — so it is the
  /// one that yields when a block is narrow because something overlaps it.
  static const _weatherWidth = 132.0;

  /// Between the marks in the block's bottom corner.
  static const _markGap = 7.0;

  /// The row those marks stand in, pinned to the bottom of the block.
  ///
  /// **Reserved out of the height before the detail lines are counted**, which
  /// is the price of putting them at the bottom rather than at the end of the
  /// last line. On a tall block it costs nothing — there are only ever three
  /// candidate lines and they all fit anyway — and on a one-hour block it costs
  /// the time range, which is the line the block's own geometry says best.
  /// Reserving is what keeps the text off them: the column is top-aligned and
  /// now ends above the row rather than under it.
  ///
  /// Tall enough for [_BlockWeather], which is the tallest thing that stands in
  /// it.
  static const _markRow = 19.0;

  /// One of the lines under the title.
  Widget _detailText(String line, Color ink) => Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.microLabel.copyWith(color: ink.withValues(alpha: 0.66), height: 1.25),
      );

  /// The name, with the repeat mark set *inside* it, wrapping onto as many
  /// lines as [_titleLines] found room for.
  ///
  /// **A `WidgetSpan` rather than a widget beside the text**, which is the whole
  /// reason this is a `Text.rich`. Put in a `Row`, the mark takes a column of
  /// its own and every wrapped line of the name is indented under the first
  /// one — a hanging indent, which is right for a bullet and wrong for a
  /// sentence that simply happens to open with a symbol. As a span the mark is
  /// the first *character* of the title: line two starts at the block's left
  /// edge, under the mark, where the eye is already looking.
  Widget _title(Color ink, int maxLines, {required bool mark}) => Text.rich(
        TextSpan(
          children: [
            if (mark)
              WidgetSpan(
                // Centred on the line it opens, not on the run of text under
                // it — the mark belongs to the first line.
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: _RepeatPageMark(ink: ink),
                ),
              ),
            TextSpan(text: event.title),
          ],
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        // **[AppText.label] at w600 — the all-day chip's own type, exactly.**
        // The band and the grid are one surface read in one glance, and a name
        // two points larger down here made the band look like a caption over
        // the real thing. Smaller also buys the blocks what they are always
        // short of: a 15-point title left a half-hour block room for its name
        // and nothing else.
        style: AppText.label.copyWith(color: ink, fontWeight: FontWeight.w600, height: 1.15),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = _blockInk(event.srcColor);
    final past = event.phaseAt(now) == EventPhase.done;
    final editable = ref.watch(_editableProvider(event.calendarId));
    final pad = height < _tight ? 5.0 : 8.0;
    // **What is hung off this appointment, counted on the grid.** Both of these
    // watch a narrowed slice of their screen's state, so ticking an article off
    // a shopping list does not rebuild the day — see `_linkedListsFor`. Every
    // agenda row called them before the grid existed; this is the same cost in
    // the same place.
    final lists = _linkedListsFor(ref, event).length;
    final tasks = _linkedTasksFor(ref, event).length;
    final kinds = (lists > 0 ? 1 : 0) + (tasks > 0 ? 1 : 0);

    // Watched unconditionally and *then* discarded if the block is too narrow
    // to carry it, rather than watched only when it will be drawn: a `watch`
    // behind an `if` is a subscription that comes and goes as a neighbouring
    // appointment is created and deleted.
    final forecast = _weatherFor(ref, event);
    final weather = forecast != null && width >= _weatherWidth ? forecast : null;

    // **The forecast stands at the block's top edge, because that edge is the
    // appointment's start.** The reading is one hour of forecast keyed on where
    // and *when* the appointment begins, so at the foot of a four-hour block it
    // read as a claim about the whole afternoon — an 18° honest at five and
    // wrong by nine. Up here the grid's own axis says which hour it means:
    // everything on a block is drawn against time running down it.
    //
    // It is the exception to the corner, and the only one. The list, the to-do
    // and the repeat are facts about the appointment entire and have no hour to
    // stand at; this has nothing else.
    final besideTitle = weather == null ? 0.0 : _BlockWeather.box;

    // **The rest stand on the floor**, not at the end of the last line: on a
    // four-hour appointment the text stops near the top and the marks stopped
    // with it, halfway up a block of empty colour. The row is reserved out of
    // the height first, so the lines above end above it.
    final wantsMarks = kinds > 0 || event.repeats;
    final reserve =
        wantsMarks && height - pad * 2 - _titleRow(context, besideTitle) >= _markRow ? _markRow : 0.0;

    final lines = _detailLines(context, event, height, width, pad, reserve, besideTitle);
    // With no floor to stand on, a repeating appointment says so in its title —
    // a block too short for any line at all, and the one case the corner does
    // not exist.
    final markInTitle = event.repeats && reserve == 0;
    final titleLines = _titleLines(
      context,
      height,
      pad,
      lines.length,
      reserve,
      math.max(besideTitle, markInTitle ? _CalendarPageMark.size : 0.0),
    );

    final marks = <Widget>[
      if (kinds > 0)
        _LinkBadges(
          lists: lists,
          tasks: tasks,
          ink: ink,
          labelled: width >= _badgeLabelWidth + _badgeLabelStep * (kinds - 1),
        ),
      if (event.repeats) _RepeatPageMark(ink: ink),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ref.read(calendarProvider.notifier).openEvent(event, headingText);
        _showEventDetailSheet(context, ref);
      },
      // The swipe that used to reveal Bearbeiten and Löschen has nowhere to go
      // on a block that is already only half a column wide, so the same two
      // actions come from a long press — the system's own menu, beside the
      // block, through the one function every menu in the app goes through.
      onLongPress: editable ? () => _openEventCardMenu(context, ref, event) : null,
      child: Opacity(
        // A finished appointment steps back rather than leaving: the day still
        // has to read as a whole, and this is what the rail's filled dots used
        // to say one row at a time.
        //
        // Lighter-handed than it looks. The block is already translucent, so
        // this multiplies an alpha rather than dimming a solid fill — 0.55 on
        // the old opaque card is about 0.08 of colour on this one, which is a
        // morning that has quietly disappeared.
        opacity: past ? 0.72 : 1,
        child: Container(
          decoration: _blockChip(event.srcColor),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              // **The calendar's colour at full strength, once per block.**
              // The fill is the same hue lightened, which is what makes a
              // pale calendar legible and also what makes two pale calendars
              // take a second look to tell apart. The bar is the undiluted
              // colour, in the one place on a block that is always the same
              // size whatever the clock gave it — a five-minute reminder and a
              // whole afternoon carry the same three points of it.
              //
              // The all-day chips above carry the same bar, and the day's
              // calendar mark moved out of them into the gutter — so the band
              // and the grid start on one edge and mark a calendar one way.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _accentBar,
                child: ColoredBox(color: event.srcColor),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(10, pad, 9, pad),
                // **A block's height comes from the clock, not from its
                // content**, so at a large accessibility text scale the title is
                // simply taller than the twenty minutes it stands for. Letting
                // it overflow the box is the honest answer — the alternative is
                // a grid whose hours are different heights — and this is what
                // keeps that from being a yellow-striped error instead of a
                // clipped line.
                child: _Unbounded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // **A repeating appointment says so before it says its
                      // name**, and says it inside the name rather than beside
                      // it — see [_title]. Leading is where a mark belongs that
                      // qualifies the whole block rather than one line of it,
                      // and it is the one position that survives every size a
                      // block comes in, including the half-hour that is its
                      // title and nothing else.
                      //
                      // Trailing the title was worse in both directions: on a
                      // long name it sat behind an ellipsis and never appeared,
                      // and on a short one it floated in the middle of the
                      // block with nothing to hold it.
                      // The forecast takes the corner the title's longest line
                      // would otherwise reach into, which is the price of
                      // standing at the start edge. Short names pay nothing and
                      // long ones wrap a word earlier.
                      if (weather != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(child: _title(ink, titleLines, mark: markInTitle)),
                            const SizedBox(width: 6),
                            _BlockWeather(reading: weather, ink: ink),
                          ],
                        )
                      else
                        _title(ink, titleLines, mark: markInTitle),
                      for (final line in lines) _detailText(line, ink),
                    ],
                  ),
                ),
              ),
              // Bounded on both sides rather than only on the right, so a wide
              // cluster runs out of room the way any row does instead of
              // reaching across the block.
              if (reserve > 0)
                Positioned(
                  left: 10,
                  right: 9,
                  bottom: pad,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < marks.length; i++) ...[
                        if (i > 0) const SizedBox(width: _markGap),
                        marks[i],
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mark a repeating appointment wears, in the corner of its block.
///
/// **The same calendar page the all-day chip carries, with several dates on it
/// instead of one.** The band above the grid and the blocks below it are one
/// surface, so their two marks are one drawing: a page with *the* date up
/// there, a page with a scatter of them down here. It says "this appointment
/// has more days than the one you are looking at" without a symbol anybody has
/// to have learned — which is more than the recurrence arrows managed, and they
/// had a second problem besides.
///
/// **Arrows could not be drawn heavily enough at this size.** Phosphor's are one
/// Regular stroke, about 1.5% of the em — two thirds of a point inside a
/// 17-point page, a hairline beside the w700 number the other page carries.
/// Every fix was a compromise: the duotone's filled layer welded on for weight,
/// a third font vendored for one glyph, or the glyph drawn by hand. Dots have no
/// such problem, because a filled dot is as bold as its radius and nothing else.
///
/// **And `AppIcons.repeat` is free now.** It named recurrence here and a Board
/// Tracker over there — one symbol for two different promises, "this comes back
/// every Tuesday" and "this is a rhythm we keep". The Tracker had already moved
/// to [AppIcons.circleDashed], whose open ring is the honest counterpart to the
/// to-do's closed one; the arrows are nobody's twin any more.
class _RepeatPageMark extends StatelessWidget {
  final Color ink;

  const _RepeatPageMark({required this.ink});

  @override
  Widget build(BuildContext context) => _CalendarPageMark(
        ink: ink,
        face: CustomPaint(
          size: const Size(_RepeatDots.width, _RepeatDots.height),
          painter: _RepeatDots(ink),
        ),
      );
}

/// The dates on the recurrence page: two rows of three, in the page's own ink.
///
/// Drawn rather than set as a string of bullets, for the reason the page itself
/// is drawn — a character is at the mercy of the font's own idea of how big a
/// dot is and where the baseline puts it, and this has to sit in the middle of a
/// box 17 points across. Six is enough to read as "several" and few enough to
/// stay six dots rather than becoming a texture.
class _RepeatDots extends CustomPainter {
  final Color ink;

  const _RepeatDots(this.ink);

  static const _columns = 3;
  static const _rows = 2;
  static const _radius = 0.95;
  static const _step = 4.2;

  static const width = (_columns - 1) * _step + _radius * 2;
  static const height = (_rows - 1) * _step + _radius * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ink;
    final left = (size.width - width) / 2 + _radius;
    final top = (size.height - height) / 2 + _radius;
    for (var row = 0; row < _rows; row++) {
      for (var column = 0; column < _columns; column++) {
        canvas.drawCircle(Offset(left + column * _step, top + row * _step), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_RepeatDots old) => old.ink != ink;
}

/// The forecast for the hour the appointment starts, in the corner with the
/// rest of the marks.
///
/// **The one mark down there that is decoration.** The list, the to-do and the
/// repeat are all facts about the appointment; this is a fact about the sky,
/// which is why it is the first thing dropped when a block is narrow because
/// something overlaps it — see [_EventBlock._weatherWidth].
///
/// **The drawing is rendered half again as large as the space it occupies**,
/// which is what makes it legible at this size, and it is not a trick. A
/// Meteocon is a 128-square with the weather in the middle of it: `cloudy`'s
/// cloud spans about 80 of those units across and barely 50 down, so a plain
/// 18-point render put a nine-point cloud on the block and the rest was
/// transparent margin. Rendering at [_art] inside a box of [_box] spends that
/// margin instead of the row's height — the ink roughly doubles and the mark
/// still stands exactly [_EventBlock._markRow] tall.
///
/// Growing the row was the other way, and it costs more than it looks: a
/// one-hour block has about 38 points under its title, so five more points of
/// mark row is the difference between one detail line and none. The place the
/// appointment is at should not come off the block to make a cloud bigger.
///
/// **The temperature still carries the answer.** Several of these drawings are
/// pale by design — an overcast cloud, a snow cloud — and no size fixes a pale
/// grey cloud on a pale chip the way two digits do. The icon says *which*
/// weather at a glance and "18°" says how much. The day strip above stacks the
/// two and can afford 30 points; see `_DayStripCell._weatherIcon`.
///
/// There is no forecast for a past appointment, one beyond the 16-day horizon
/// or a household with no address — `_weatherFor` answers null and the mark
/// simply is not there, which is how every weather failure in this app resolves.
class _BlockWeather extends StatelessWidget {
  final WeatherReading reading;
  final Color ink;

  const _BlockWeather({required this.reading, required this.ink});

  /// What the mark occupies. Read by the block too, which has to know how tall
  /// the title's row becomes when this stands in it.
  static const box = 19.0;

  /// What the drawing is rendered at. Bounded by the widest art in the set
  /// rather than by the box: `clear-day`'s rays span 93 of its 128 units, so at
  /// this size the sun measures 19.6 points and just fills the row it is
  /// centred in. Every cloud in the set spans about 65 — half its square — and
  /// simply gains, from a nine-point smudge to a fourteen-point cloud.
  static const _art = 27.0;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: box,
            height: box,
            child: OverflowBox(
              maxWidth: _art,
              maxHeight: _art,
              child: SvgPicture.asset(reading.iconAsset, width: _art, height: _art),
            ),
          ),
          // Three rather than two: the widest drawings reach a point past the
          // box on each side, and the degrees must not be what they land on.
          const SizedBox(width: 3),
          Text(
            reading.temperatureLabel,
            maxLines: 1,
            style: AppText.microLabel.copyWith(color: ink.withValues(alpha: 0.66), height: 1.25),
          ),
        ],
      );
}

/// What a household hung off this appointment: the shopping list, the to-do.
///
/// **The one thing on a block that is not already somewhere else.** The name is
/// in the calendar, the hour is the block's own position, the length is its
/// height — but that the Elternabend has a list against it exists nowhere on
/// the grid, and finding it meant opening the sheet to discover whether there
/// was anything to open it for.
///
/// **Two forms, and the block's width picks.** Wide enough and it spells itself
/// out — "1 Liste" — because a count is the useful half of it and a glyph alone
/// cannot say two. Narrower and the glyph stands alone, which still answers the
/// only question a glance is asking: is there something here. It is never
/// dropped for want of room, because the fallback is smaller than the thing it
/// falls back from.
///
/// **Flat, not a pill.** The block is already a chip in its calendar's colour,
/// and a second chip inside it is a card pretending to be a row — the same
/// reason the all-day pills carry no accent bar. It takes the ink and the
/// weight of the line it shares, so it reads as the end of that line.
class _LinkBadges extends StatelessWidget {
  final int lists;
  final int tasks;
  final Color ink;

  /// Whether the counts are spelled out beside the glyphs. Decided by the
  /// block's width upstream, where [_EventBlock._badgeLabelWidth] is measured.
  final bool labelled;

  const _LinkBadges({required this.lists, required this.tasks, required this.ink, required this.labelled});

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final tint = ink.withValues(alpha: 0.66);

    Widget badge(IconData icon, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: AppGlyph.inline, color: tint),
            if (labelled) ...[
              const SizedBox(width: 3),
              Text(
                label,
                maxLines: 1,
                style: AppText.microLabel.copyWith(color: tint, height: 1.25),
              ),
            ],
          ],
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lists > 0) badge(AppIcons.listChecks, L.s.linkedListCount(lists)),
        if (lists > 0 && tasks > 0) const SizedBox(width: _gap),
        if (tasks > 0) badge(AppIcons.checkCircle, L.s.linkedTaskCount(tasks)),
      ],
    );
  }
}

/// A to-do that named an hour, standing at that hour.
///
/// **Deliberately not a coloured block.** Every appointment on the grid is a
/// chip in its calendar's colour, so a to-do drawn the same way would be an
/// appointment as far as a glance is concerned. It is outlined instead (see
/// [_todoChip]), and carries the Board's own check.
class _TodoBlock extends ConsumerWidget {
  final BoardTask task;
  final Color accent;
  final double height;

  const _TodoBlock({required this.task, required this.accent, required this.height});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = whoBadge(
      assigneeId: task.assigneeId,
      visibility: task.visibility,
      sharedWith: task.sharedWith,
      members: ref.watch(householdMembersProvider),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: task.done ? 1 : 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, strike, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Its tap already opens the editor, so there is no second sheet a menu
        // or a swipe could offer.
        onTap: () => openTaskSheet(context, ref, task: task),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
          // The same shape as every appointment beside it, outlined instead
          // of filled — see [_todoChip].
          decoration: _todoChip(),
          clipBehavior: Clip.hardEdge,
          child: _Unbounded(
            child: Row(
              children: [
                // The face first, the way the agenda card had it. Whose to-do it
                // is, is the question a household asks of one of these before it
                // asks what it says — and it is the one thing from the old card
                // small enough to survive the move onto the grid.
                Semantics(
                  label: who.label,
                  excludeSemantics: true,
                  child: WhoAvatars(who: who, size: 19, fontSize: 9),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StrikeThrough(
                    progress: strike,
                    color: AppColors.doneInk,
                    child: Text(
                      task.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The same type as the appointment blocks beside it.
                      // They stand on one grid; a to-do set two points larger
                      // would read as the important one.
                      style: AppText.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Color.lerp(AppColors.ink, AppColors.doneInk, strike),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                CheckOffButton(
                  progress: strike,
                  accent: accent,
                  onTap: () => ref.read(boardProvider.notifier).toggle(task),
                  size: 20,
                  filled: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets a block's content be taller than the block without Flutter painting an
/// overflow stripe over it. See [_EventBlock].
class _Unbounded extends StatelessWidget {
  final Widget child;

  const _Unbounded({required this.child});

  @override
  Widget build(BuildContext context) => ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: 0,
          maxHeight: double.infinity,
          child: child,
        ),
      );
}

/// Whether one calendar takes writes — Ferien, Abfall and a read-only provider
/// calendar do not, and a block on one offers no menu.
///
/// A family of providers rather than a `watch` of the whole notifier: every
/// block on the grid asks this, and the answer changes when a connection does,
/// not when the clock ticks.
final _editableProvider = Provider.family<bool, String>(
  (ref, calendarId) => ref.watch(
    calendarProvider.select((s) => s.sourceById(calendarId)?.editable ?? false),
  ),
);

/// Everything true of the whole day, above the clock: the Feiertag, the all-day
/// events, and the to-dos that name no hour.
///
/// **None of it belongs on a grid.** An all-day event is not at a point in the
/// day, a to-do owed by the end of it is not either, and a Feiertag is a property
/// of the date itself — giving any of them a position would be inventing one.
/// This is the band Apple, Outlook and Teams all put in the same place for the
/// same reason.
///
/// **One row of chips, not a stack of cards.** Each of these used to take a
/// full-width row at [AppText.itemTitle], so a day with Ferien and a bin pickup
/// spent two appointments' worth of height before the clock started — and sat
/// directly under a Feiertag chip drawn at half the size, which made two things
/// of exactly the same kind look like two different kinds of thing. They are all
/// [_HolidayChip]'s shape and scale now, and the Feiertag is simply the first of
/// them rather than a row of its own.
///
/// **One row, always.** A [Wrap] was tried and it is not the same thing: on a day
/// with a Feiertag, Ferien and a bin pickup the chips fell onto a second and
/// third line, and the band went back to costing an appointment's worth of
/// height before the clock had started — which is the whole reason the pills
/// became chips. It scrolls sideways instead. What that costs is a chip off the
/// right edge on a very full day; what it buys is a band that is the same height
/// on every day of the year, which is what makes the day below it sit still as
/// you move between days.
class _DayBand extends StatelessWidget {
  final _DayPlan plan;
  final GermanHoliday? holiday;

  /// The day being drawn — the number on the calendar page in the gutter.
  final DateTime day;

  final String headingText;
  final Color accent;
  final bool compact;

  /// Whether there is a grid under the band to be separated *from*. On a day of
  /// nothing but all-day events the rule would be the last thing on the card,
  /// underlining a row rather than dividing two — so it is not drawn.
  final bool divided;

  const _DayBand({
    required this.plan,
    required this.holiday,
    required this.day,
    required this.headingText,
    required this.accent,
    required this.compact,
    required this.divided,
  });

  /// A long title is capped rather than left to push everything after it off the
  /// screen on its own. Tighter than it was as a [Wrap], because a row that
  /// scrolls wants the second chip's shoulder showing.
  static const _maxChipWidth = 210.0;

  static const _gap = 7.0;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (holiday case final holiday?) _HolidayChip(holiday: holiday, accent: accent),
      for (final event in plan.allDay)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxChipWidth),
          child: _AllDayPill(event: event, headingText: headingText),
        ),
      for (final task in plan.untimedTodos)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxChipWidth),
          child: _UntimedTodoChip(task: task, accent: accent),
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // **The day's page stands where an hour label would**, in the
              // grid's own gutter and right-aligned like the labels, so the
              // chips beside it start on the blocks' left edge. It is one mark
              // for the whole band, where every all-day chip used to carry its
              // own copy of the same date.
              SizedBox(
                width: _gutter,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _DayPageMark(day: day.day, ink: AppColors.muted),
                ),
              ),
              const SizedBox(width: _gutterGap),
              Expanded(
                // Cut on the left only: a chip scrolled back must not slide
                // over the page mark, but the right edge still runs past the
                // card — a chip cut by the screen is what says there is another
                // one, exactly as the day strip above does it.
                child: ClipRect(
                  clipper: const _ClipLeftEdge(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        for (var i = 0; i < chips.length; i++) ...[
                          if (i > 0) const SizedBox(width: _gap),
                          chips[i],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // **One rule, where twelve were refused.** The hour lines came off
          // the day because a hairline drawn over and over is paper the
          // appointments have to compete with; a single one that says "above
          // this is the whole day, below it is the clock" is the opposite — it
          // is read once and then stops asking. Home needs it most: the heading
          // that names the section on the calendar screen is not there, so the
          // rule is the only thing telling the two apart.
          //
          // Inset to the card's content rather than run to its edges, although
          // the chips above it scroll past both: a rule is a statement about
          // the column it divides, and a full-bleed one would be a statement
          // about the card.
          if (divided) ...[
            SizedBox(height: compact ? 11 : 13),
            Divider(height: 0.5, thickness: 0.5, color: AppColors.hairline),
          ],
        ],
      ),
    );
  }
}

/// Clips a band's left edge and nothing else. See [_DayBand].
class _ClipLeftEdge extends CustomClipper<Rect> {
  const _ClipLeftEdge();

  /// Past the right, top and bottom by far more than a chip or the card's
  /// padding — the clip is only there to stop at the gutter.
  static const _reach = 10000.0;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -_reach, size.width + _reach, size.height + _reach);

  @override
  bool shouldReclip(_ClipLeftEdge oldClipper) => false;
}

/// One all-day event in the band — [_HolidayChip]'s scale, in its calendar's
/// colour, with a timeline block's accent bar down the left.
class _AllDayPill extends ConsumerWidget {
  final CalendarEvent event;
  final String headingText;

  const _AllDayPill({required this.event, required this.headingText});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = _blockInk(event.srcColor);
    final editable = ref.watch(_editableProvider(event.calendarId));
    // A shared feed says what it is with a mark, as the Feiertag chip beside it
    // does with its confetti. The same glyphs their tiles wear in Settings
    // (`CalendarProvider.icon`), so a bin day reads as the Abfall calendar the
    // family connected rather than as one more appointment.
    final feedKind = ref.watch(calendarProvider.select((s) => s.sourceById(event.calendarId)?.feedKind ?? ''));
    final feedIcon = switch (feedKind) {
      'abfall' => AppIcons.recycle,
      'ferien' => AppIcons.graduationCap,
      _ => null,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ref.read(calendarProvider.notifier).openEvent(event, headingText);
        _showEventDetailSheet(context, ref);
      },
      onLongPress: editable ? () => _openEventCardMenu(context, ref, event) : null,
      // **The block's radius, not a capsule**: a bar down the side of a pill is
      // cut to a sliver by its corners, and the chip and the blocks under it
      // should read as the same object at two heights.
      child: Container(
        decoration: _blockChip(event.srcColor),
        clipBehavior: Clip.hardEdge,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: _accentBar, child: ColoredBox(color: event.srcColor)),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // [_HolidayChip]'s size and gap, so the band's marks match.
                      if (feedIcon != null) ...[
                        AppIcon(feedIcon, size: 14, color: ink),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label.copyWith(color: ink, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // "3 Tage" for a span, and nothing at all for a single
                      // day: a chip in the all-day band already says it is all
                      // day, and "Ganztägig" printed beside the name was the
                      // band's own heading repeated once per chip.
                      if (event.days.length > 1) ...[
                        const SizedBox(width: 8),
                        Text(
                          event.durationLabel,
                          maxLines: 1,
                          style: AppText.microLabel.copyWith(color: ink.withValues(alpha: 0.66)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A calendar page with the date on it — the mark the all-day band carries in
/// the grid's gutter.
class _DayPageMark extends StatelessWidget {
  final int day;
  final Color ink;

  const _DayPageMark({required this.day, required this.ink});

  @override
  Widget build(BuildContext context) => _CalendarPageMark(
        ink: ink,
        face: Text(
          '$day',
          // A glyph rather than text: at an accessibility scale the number
          // would break out of the page long before it helped anybody read it,
          // and the chip's own label beside it is what does scale.
          textScaler: TextScaler.noScaling,
          maxLines: 1,
          style: TextStyle(fontSize: _CalendarPageMark.faceText, fontWeight: FontWeight.w700, color: ink, height: 1),
        ),
      );
}

/// The page both of the day's calendar marks are drawn on: a bound, a border,
/// and whatever the mark has to say inside it.
///
/// **Drawn rather than picked from the icon font**, which is the one place in
/// the app that is true. Every glyph in [AppIcons] is a shape that means
/// something; the date has to *say* something, and no font ships thirty-one of
/// those. Once the page existed for the date it became the frame the
/// recurrence mark wanted too — the alternative was an all-day chip wearing a
/// drawing and a repeating block wearing a glyph, two marks about the calendar
/// that looked nothing like each other.
///
/// Four rectangles and a face, cheaper than an asset per day and correct in
/// both palettes because it is built from the chip's own ink.
class _CalendarPageMark extends StatelessWidget {
  final Color ink;

  /// What is written on the page: the day's number, or a glyph.
  final Widget face;

  const _CalendarPageMark({required this.ink, required this.face});

  /// Read by the blocks too: a title's row is this tall whenever a mark stands
  /// in it, which is taller than the title's own type.
  static const size = 17.0;

  /// The bound at the top of the page. Enough to read as one at this size and
  /// no more, or the face loses the room it needs.
  static const _band = 4.0;
  static const _radius = 4.5;

  /// The number on the dated page. Not an [AppGlyph] tier and deliberately so:
  /// it is part of a drawing, measured against the page around it rather than
  /// against a word beside it. The recurrence page's dots are measured the same
  /// way, in [_RepeatDots].
  static const faceText = 8.5;

  @override
  Widget build(BuildContext context) {
    final line = ink.withValues(alpha: 0.55);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: line, width: 1.2),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _band,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: line,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(_radius - 1.2)),
              ),
            ),
          ),
          Positioned(
            top: _band,
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(child: face),
          ),
        ],
      ),
    );
  }
}

/// A to-do owed by the end of the day, in the band beside the all-day events.
///
/// The same capsule, outlined rather than filled with a calendar's colour (see
/// [_todoChip]), and carrying the Board's own check.
class _UntimedTodoChip extends ConsumerWidget {
  final BoardTask task;
  final Color accent;

  const _UntimedTodoChip({required this.task, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: task.done ? 1 : 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, strike, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openTaskSheet(context, ref, task: task),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 5, 5, 5),
          decoration: _todoChip(radius: _chipRadius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: StrikeThrough(
                  progress: strike,
                  color: AppColors.doneInk,
                  child: Text(
                    task.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(AppColors.ink, AppColors.doneInk, strike),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              CheckOffButton(
                progress: strike,
                accent: accent,
                onTap: () => ref.read(boardProvider.notifier).toggle(task),
                size: 19,
                filled: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
