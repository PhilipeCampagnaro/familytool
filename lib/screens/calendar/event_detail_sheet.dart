part of '../calendar_screen.dart';

// ---------------------------------------------------------------------------
// Event detail sheet
// ---------------------------------------------------------------------------

/// The event-detail sheet's header: a centered title with the close button
/// beside it — the same single row every other sheet in the app has
/// (`_AppSheetBody._defaultHeader`), whose shape this copies.
///
/// The word "Termin", not the event's own name. The name is
/// [_buildEventHeadline], right below in the body, where it has the full width
/// and may wrap; up here it would only ever be the same line ellipsized, and
/// two copies of a title 30pt apart is a worse header than a plain label.
///
/// It replaced a collapsing header that opened with a 23pt left-aligned title
/// and shrank it as the body scrolled, for two reasons. A heading that size
/// belongs to a *screen*; over the first card of a sheet it read as a second
/// title competing with the one behind it. And the frosted backdrop that header
/// needed put a `BackdropFilter` under a native glass button inside a modal
/// route, where on device the title and the chips under it did not paint at all
/// — the same class of platform-view compositing trap `_defaultHeader` is
/// written around. A plain row has neither problem, and the source/owner chips
/// moved into the body, over the first card.
Widget _buildEventDetailHeader(BuildContext context, WidgetRef ref) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: SizedBox(
      height: _eventDetailHeaderHeight,
      child: Stack(
        children: [
          // Painted *before* the close button and spanning the whole row, never
          // as a `Row` sibling of it: [GlassIconButton] is a native platform
          // view on iOS, and Flutter content painted after one lands in a
          // composited overlay layer that can be dropped. Spanning the row also
          // makes "centered" mean centered on the sheet rather than in what the
          // button leaves over.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _eventDetailHeaderHeight + 14),
              child: Center(
                child: Text(
                  L.s.eventLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.sheetTitle,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GlassIconButton(
              icon: LucideIcons.x,
              onTap: () {
                ref.read(calendarProvider.notifier).closeEvent();
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// The event's full title, at the top of the body where it has the sheet's
/// whole width and may wrap — "Ariane beim Jobcenter - Raum 214" is a perfectly
/// ordinary appointment name and the header row can only ever ellipsize it.
///
/// [AppText.cardTitle], not the 23pt [AppText.detailTitle] the old collapsing
/// header used: at that size it read as a second screen title competing with
/// the sheet's own, which is why that header went away in the first place.
/// Three lines is where it stops — past that a pasted meeting subject would
/// push the date and the map off the sheet.
Widget _buildEventHeadline(String title) {
  return Text(
    title,
    maxLines: 3,
    overflow: TextOverflow.ellipsis,
    style: AppText.cardTitle.copyWith(height: 1.3),
  );
}

/// Where the event comes from and whose it is: the two chips that used to sit
/// on the header's collapsing second row.
///
/// On the gray body they are white pills rather than [AppColors.surfaceAlt]
/// ones — that fill is a shade of the gray they would now be sitting on.
Widget _buildEventChips(CalendarEvent e) {
  final tone = AppTones.list[e.ownerTone];

  return Row(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: e.srcColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(e.source, style: AppText.microLabel.copyWith(color: AppColors.inkSecondary)),
        ]),
      ),
      // An event has no owner until there is an account behind the app; the
      // chip is dropped rather than shown blank.
      if (e.owner.isNotEmpty) ...[
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.fromLTRB(3, 3, 11, 3),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Avatar(size: 21, bg: tone.bg, fg: tone.fg, initials: e.ownerInitial, fontSize: 9),
            const SizedBox(width: 6),
            Text(e.owner, style: AppText.microLabel.copyWith(color: AppColors.inkSecondary)),
          ]),
        ),
      ],
    ],
  );
}

/// Height of the event-detail sheet's action row. The trash [GlassIconButton]
/// is square, so this is also its width — it's sized from the "Bearbeiten"
/// pill beside it, whose height is its 14pt padding top and bottom around a
/// ~22pt line of Poppins 15.
const _detailActionHeight = 50.0;

/// The header row's height — [GlassIconButton]'s own diameter, so the title
/// line and the button are one row rather than two stacked ones.
const _eventDetailHeaderHeight = 40.0;

void _showEventDetailSheet(BuildContext context, WidgetRef ref) {
  showAppSheet(
    context: context,
    heightFactor: 0.88,
    header: Consumer(
      builder: (context, ref, _) => _buildEventDetailHeader(context, ref),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(calendarProvider);
        final e = state.openEvent;
        final accent = Theme.of(context).colorScheme.primary;
        if (e == null) return const SizedBox.shrink();
        final weather = _weatherFor(ref, e);

        return Column(
          // Stretch, not start: under `start` every card is only as wide as its
          // own content, which nobody notices while the cards hold full-width
          // rows — and then the notes card, whose widest line is the word
          // "Notizen", ships as a stub beside them.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (e.title.trim().isNotEmpty) ...[
              _buildEventHeadline(e.title),
              const SizedBox(height: 12),
            ],
            _buildEventChips(e),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(LucideIcons.calendar, size: 15, color: AppColors.muted),
                            SizedBox(width: 9),
                            Text(L.s.eventLabel, style: AppText.microLabel.copyWith(letterSpacing: 0.3)),
                          ]),
                          const SizedBox(height: 9),
                          Text(state.openEventDateLine, style: AppText.itemTitle),
                          const SizedBox(height: 2),
                          Text(e.timeRangeLabel, style: AppText.caption.copyWith(fontWeight: FontWeight.w300, color: AppColors.inkTertiary)),
                        ],
                      ),
                    ),
                  ),
                  // Same as the agenda row: no forecast, no card — and the date
                  // beside it then takes the full width rather than sitting next
                  // to an empty box.
                  if (weather != null) ...[
                    const SizedBox(width: 10),
                    _WeatherCard(weather: weather),
                  ],
                ],
              ),
            ),
            // A card for a place the event doesn't have is an empty row over a
            // map of nowhere — a Ferien block has no location and shouldn't
            // pretend to.
            if (e.loc.isNotEmpty) ...[
              const SizedBox(height: 12),
              _EventLocationCard(event: e, accent: accent),
            ],
            // Notes, on the other hand, are shown empty on purpose: every event
            // has this card, so the sheet has one shape and "there are no notes
            // on this one" is something you can read off it.
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.s.notes, style: AppText.microLabel),
                  const SizedBox(height: 6),
                  // The same hint the event form's notes field shows, so an
                  // empty card is a line of text rather than a label over a
                  // collapsed nothing — and it says how to fill it.
                  e.body.trim().isEmpty
                      ? Text(L.s.addNotes, style: AppText.body.copyWith(color: AppColors.mutedLight))
                      : Text(e.body, style: AppText.body),
                ],
              ),
            ),
            // Wider than the 12pt rhythm between the detail cards above: these
            // are the sheet's actions, not another card, so they need to read as
            // a separate group rather than crowding the last one.
            const SizedBox(height: 22),
            // Hidden for anything proxied from a connected account or a public
            // feed: Aporah keeps no copy of those, so there is nothing here to
            // edit or delete. The source app — or the Stadtreinigung — owns them.
            if (state.sourceById(e.calendarId)?.editable ?? false)
              Row(
                children: [
                  // Same size as the pill beside it is tall, so the pair reads as
                  // one row of controls in the same material rather than a button
                  // and a card. Plain ink, like every other icon in the app: red
                  // is how the confirm dialog's "Löschen" reads, and spending it
                  // out here too made a button you have not pressed yet look like
                  // the consequence of pressing it.
                  GlassIconButton(
                    icon: LucideIcons.trash,
                    size: _detailActionHeight,
                    iconSize: 18,
                    onTap: () => _confirmDeleteEvent(context, ref, e, closeParentSheet: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassAccentButton(
                      label: L.s.edit,
                      expand: true,
                      onTap: () => _openEditEventSheet(context, ref, e),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    ),
  );
}

/// The forecast at the appointment, beside the date it happens on.
///
/// **The one card in the app that is not white.** It wears the weather itself —
/// amber for a sunny afternoon, slate for an overcast one, ink-blue for rain —
/// which is the fastest way to answer "do we need coats?" from across the room,
/// before any number has been read. The wash and the ink both come from
/// [WeatherReading.skin]; see [WeatherSkin] for why it is a pale wash and not
/// the dark sky a weather app would use.
///
/// The agenda row stays plain on purpose. Ten cards down a day, each in its own
/// colour, would turn the calendar into a chart of the weather rather than a
/// list of the family's day — so out there the icon carries it alone.
class _WeatherCard extends StatelessWidget {
  final WeatherReading weather;

  const _WeatherCard({required this.weather});

  @override
  Widget build(BuildContext context) {
    final skin = weather.skin;

    return Container(
      width: 126,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        gradient: skin.gradient,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Drawn at its own colours — no `colorFilter`. A Meteocons file is a
          // little illustration, and flattening it to one tint is exactly what
          // this card moved away from.
          SvgPicture.asset(weather.iconAsset, width: 46, height: 46),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Text(weather.temperatureLabel, style: AppText.statValue.copyWith(color: skin.ink)),
              // The condition in words is what makes the colour readable as
              // weather rather than as decoration, so it keeps full weight
              // instead of the tertiary grey a caption would take.
              Text(weather.label, style: AppText.label.copyWith(color: shade(skin.ink, .78))),
            ],
          ),
        ],
      ),
    );
  }
}

/// The event's place: the address row, a real map of it, and the button that
/// hands it to a navigation app.
///
/// The map is a still image rendered on the device by MapKit
/// ([mapSnapshot]) — not a widget, not a tile server, and nothing about where
/// the family is going leaving the phone. It needs the card's real width, so
/// the request is started from the [LayoutBuilder] that knows it rather than
/// from `initState`.
///
/// A place the geocoder cannot find simply has no map: the row stays, tapping
/// it still offers the route, and the navigation app gets the words instead of
/// a point.
class _EventLocationCard extends StatefulWidget {
  final CalendarEvent event;
  final Color accent;

  const _EventLocationCard({required this.event, required this.accent});

  @override
  State<_EventLocationCard> createState() => _EventLocationCardState();
}

class _EventLocationCardState extends State<_EventLocationCard> {
  /// The map's height, unchanged from the placeholder card it replaces.
  static const _mapHeight = 132.0;

  /// Both the address row and the "Route" pill open the menu from *here*, the
  /// row at the top of the card. Anchored to the pill instead, the menu drops
  /// into the sheet's action row — and "Bearbeiten" and the trash button are
  /// native glass platform views, which composite above anything Flutter paints
  /// (the same reason the menu flips above its anchor before it reaches the
  /// bottom nav). Under the row it opens over the map, which is ours to paint.
  final _rowAnchor = GlobalKey();

  /// Identifies the request whose answer we are showing, so a resize or a
  /// theme flip supersedes an older one still in flight instead of racing it.
  String? _requested;
  MapView? _map;
  bool _resolved = false;

  /// What goes to the geocoder: both lines when there are two, since
  /// "Musterstraße 1" alone is in every second German town.
  String get _query {
    final e = widget.event;
    return e.locSub.isEmpty ? e.loc : '${e.loc}, ${e.locSub}';
  }

  /// Started from `build` on purpose (see the class doc). Nothing is set
  /// synchronously here — the `await` puts the `setState` after this frame,
  /// which is what makes calling it from a [LayoutBuilder] legal.
  Future<void> _load(double width, bool dark, double scale) async {
    final key = '$_query|${width.round()}|$dark';
    if (key == _requested) return;
    _requested = key;

    var view = await mapSnapshot(
      query: _query,
      width: width,
      height: _mapHeight,
      scale: scale,
      dark: dark,
    );
    // "Turnhalle, Raum 2" is not an address anybody can place; the first line
    // on its own usually is.
    if (view == null && _query != widget.event.loc) {
      view = await mapSnapshot(
        query: widget.event.loc,
        width: width,
        height: _mapHeight,
        scale: scale,
        dark: dark,
      );
    }
    if (!mounted || key != _requested) return;
    setState(() {
      _map = view;
      _resolved = true;
    });
  }

  /// Waze or Google Maps — the same two the old web app offered. Deliberately
  /// not Apple Maps as a third: this is the household's *usual* navigation app,
  /// and the system share sheet is not what a two-item choice should feel like.
  ///
  /// The **system** action sheet, not the app's own [showAnchoredMenu] dropdown
  /// every other menu uses. This one opens from inside a sheet that carries
  /// native glass buttons, and there a Flutter-painted menu is composited after
  /// a platform view: on device it opened, took the taps behind it, and never
  /// appeared — the same layer-dropping trap that ate this sheet's title when
  /// it still had a frosted header. UIKit puts its own sheet above everything,
  /// so there is no layer left to lose. Off iOS there is nothing to present and
  /// the dropdown is still the fallback.
  Future<void> _openRouteMenu() async {
    const apps = NavigationApp.values;
    final picked = await showNativeActionSheet(
      title: _query,
      options: [for (final app in apps) app.label],
      cancelLabel: L.s.cancel,
      dark: AppColors.isDark,
    );
    if (picked == actionSheetCancelled) return;
    if (picked != null) {
      await openNavigation(apps[picked], query: _query, latitude: _map?.latitude, longitude: _map?.longitude);
      return;
    }
    if (!mounted) return;
    showAnchoredMenu(
      context: context,
      anchorKey: _rowAnchor,
      items: [
        for (final app in apps)
          AnchoredMenuItem(
            label: app.label,
            icon: switch (app) {
              NavigationApp.waze => LucideIcons.navigation,
              NavigationApp.googleMaps => LucideIcons.map,
            },
            onSelected: () => openNavigation(
              app,
              query: _query,
              latitude: _map?.latitude,
              longitude: _map?.longitude,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final accent = widget.accent;

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            key: _rowAnchor,
            behavior: HitTestBehavior.opaque,
            onTap: _openRouteMenu,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle), alignment: Alignment.center, child: Icon(LucideIcons.mapPin, size: 18, color: accent)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.loc, style: AppText.itemTitle),
                        if (e.locSub.isNotEmpty) Text(e.locSub, style: AppText.label),
                      ],
                    ),
                  ),
                  // No trailing chevron: this row opens the route menu right
                  // under itself, it does not push a screen, and a chevron
                  // promises the second thing.
                ],
              ),
            ),
          ),
          // An online meeting has a link, not a place on a map.
          if (!e.online)
            LayoutBuilder(
              builder: (context, constraints) {
                _load(
                  constraints.maxWidth,
                  Theme.of(context).brightness == Brightness.dark,
                  MediaQuery.devicePixelRatioOf(context),
                );
                return _buildMap(accent);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMap(Color accent) {
    final map = _map;
    // Nothing at all once we know there is nothing to draw — the card ends at
    // the row rather than keeping an empty gray box open under it.
    if (_resolved && map == null) return const SizedBox.shrink();

    return Container(
      height: _mapHeight,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(15)),
      clipBehavior: Clip.antiAlias,
      // The gray box is what the geocode and the render happen behind, so the
      // map fades in over it rather than the card jumping into place.
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: map == null
            ? const SizedBox.expand()
            : Stack(
                key: ValueKey(_requested),
                children: [
                  Positioned.fill(child: Image.memory(map.image, fit: BoxFit.cover, gaplessPlayback: true)),
                  Align(
                    alignment: Alignment.center,
                    // The snapshot is centred on the address, so the pin's
                    // *tip* has to land there — hence the lift by half its
                    // height rather than a plain centre.
                    child: Transform.translate(
                      offset: const Offset(0, -_MapPin.height / 2),
                      child: _MapPin(color: accent, ring: AppColors.surface),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openRouteMenu,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: const BorderRadius.all(Radius.circular(13)), boxShadow: AppShadows.card),
                        child: Text(L.s.route, style: AppText.microLabel.copyWith(color: accent)),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The marker over the geocoded address on the map snapshot.
///
/// Drawn rather than assembled out of a `BorderRadius` with one square corner:
/// that shape is a rounded square with a spur, it points diagonally at nothing,
/// and there is no way to make its tip a real point. This is the teardrop every
/// map app draws — a circular head, two tangents converging on the tip, a white
/// ring and a shadow so it survives being dropped on a park or a rooftop of
/// about its own colour, and a hole in the middle so it reads as a pin at 22pt.
class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.ring});

  final Color color;

  /// The outline, the app's card colour — so the pin stays legible on light and
  /// dark map imagery alike.
  final Color ring;

  static const height = 28.0;
  static const size = Size(22, height);

  @override
  Widget build(BuildContext context) => CustomPaint(size: size, painter: _MapPinPainter(color: color, ring: ring));
}

class _MapPinPainter extends CustomPainter {
  const _MapPinPainter({required this.color, required this.ring});

  final Color color;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final radius = (size.width - stroke) / 2;
    final head = Offset(size.width / 2, stroke / 2 + radius);
    final tip = Offset(size.width / 2, size.height - stroke / 2);

    // Where the two straight sides leave the head: the tangent points from the
    // tip, so the head and the tail meet without a corner.
    final spread = math.acos(radius / (tip.dy - head.dy));
    final path = Path()
      ..addArc(Rect.fromCircle(center: head, radius: radius), math.pi / 2 + spread, 2 * math.pi - 2 * spread)
      ..lineTo(tip.dx, tip.dy)
      ..close();

    canvas.drawPath(
      path.shift(const Offset(0, 1)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawCircle(head, radius * 0.36, Paint()..color = ring);
  }

  @override
  bool shouldRepaint(_MapPinPainter oldDelegate) => oldDelegate.color != color || oldDelegate.ring != ring;
}

/// [closeParentSheet] should only be `true` when called from within the
/// event detail sheet itself (closing it after delete) — the swipe-action
/// entry point on the agenda card calls this directly from the screen, with
/// no parent sheet route to pop.
void _confirmDeleteEvent(BuildContext context, WidgetRef ref, CalendarEvent event, {bool closeParentSheet = false}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(L.s.deleteEventQuestion),
      content: Text(L.s.deleteEventBody(event.title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(L.s.cancel),
        ),
        TextButton(
          onPressed: () async {
            // Before the pops: [context] is the sheet's own when the delete came
            // from inside it, and that route is about to go.
            final confirm = confirmChipOf(context);
            final notifier = ref.read(calendarProvider.notifier);
            final deleting = notifier.deleteEvent(event);
            Navigator.of(dialogContext).pop();
            if (closeParentSheet) Navigator.of(context).pop();
            if (await deleting) {
              confirm(L.s.eventDeleted, undo: () => notifier.restoreEvent(event));
            }
          },
          child: Text(L.s.delete, style: AppText.rowTitle.copyWith(color: AppColors.danger)),
        ),
      ],
    ),
  );
}
