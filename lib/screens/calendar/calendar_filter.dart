part of '../calendar_screen.dart';

// Filtering the visible calendars: the glass dropdown that replaces the chip
// row once the header has collapsed, and the popup routes behind it and the
// chips. The chips themselves live with the header in calendar_screen.dart.

/// Compact "liquid glass" dropdown standing in for the filter chip row once
/// the header has collapsed — the chips don't fit a collapsed header, so this
/// pins the filter's colours + chevron in the title row itself, opening a
/// native-feeling glass menu (dot + full name per calendar) to pick a filter
/// from. Only visible while collapsed; see [_TitleRow.leading].
///
/// **It says how many and whose, not "N Kalender".** Spelling the count out in
/// words made the one control on the left of a *centred* title wide enough to
/// reach it — and the word was the half of it carrying no information, since
/// what a reader wants back from a filter is which calendars survived it. So a
/// selection is its count beside up to [_maxDots] of the calendars' own
/// colours, overlapping the way [AvatarStack] overlaps a household: the
/// colours are the same ones the chips, the menu rows and the events
/// themselves wear. One calendar is its dot alone — a "1" beside a single
/// colour counts something nobody was asked to count.
class _CalendarFilterButton extends ConsumerWidget {
  final CalendarScreenState state;

  const _CalendarFilterButton({required this.state});

  /// The filter's colours, in the order the calendars are *listed* rather than
  /// the order they come out of the set — a Set has no order, so reading them
  /// out of it would reshuffle the dots on an unrelated rebuild.
  ///
  /// Capped at [_maxDots]: the count beside them is what says how many there
  /// really are, and a stack that grew with the selection would walk into the
  /// title it sits beside.
  List<Color> get _dotColors {
    final filter = state.calendarFilter;
    if (filter == null) return const [];
    final colors = <Color>[];
    for (final src in state.calendars) {
      if (!filter.contains(src.id)) continue;
      colors.add(src.color);
      if (colors.length == _maxDots) break;
    }
    // A selection emptied to nothing still has to draw something, and muted is
    // what the menu's own "Alle" row wears.
    return colors.isEmpty ? [AppColors.muted] : colors;
  }

  /// The "Alle" chip's own multi-select list, plus the to-do row — the system's
  /// menu where there is one, the app's panel where there isn't.
  ///
  /// It used to *replace* the filter with one row's worth and close, which made
  /// the one control left once the header had collapsed a single-choice picker
  /// standing in for a row of chips that can build any set. Every row now
  /// **keeps the menu open** and toggles, exactly like
  /// [_AllCalendarsChipState._open]: a tick can move the others (untick one
  /// while "Alle" is lit and every remaining calendar becomes explicitly
  /// ticked), so each tap pushes the whole set back with
  /// [updateNativeMenuSelection].
  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final button = context.findRenderObject() as RenderBox;
    final anchor = button.localToGlobal(Offset.zero) & button.size;
    final notifier = ref.read(calendarProvider.notifier);
    final current = ref.read(calendarProvider);

    // Row 0 is the to-do overlay, row 1 "Alle"; every later row is a calendar.
    const tasksRow = 0;
    final ids = <String?>[null, null];
    List<bool> statesOf() {
      final s = ref.read(calendarProvider);
      final filter = s.calendarFilter;
      return [
        s.showTasks,
        filter == null,
        for (final id in ids.skip(2)) filter == null || filter.contains(id),
      ];
    }

    final options = <NativeMenuOption>[
      // First and in its own section, the same place and the same reason as the
      // chip row's own to-do chip. Every row under it answers "which
      // calendars"; this one does not.
      NativeMenuOption(
        L.s.todosChip,
        symbol: 'checkmark.circle',
        selected: current.showTasks,
        keepsOpen: true,
      ),
      NativeMenuOption(
        L.s.all,
        // Two people rather than a dot: a dot stands for a calendar of that
        // colour, and there is no "Alle" calendar for it to stand for.
        symbol: 'person.2',
        selected: current.calendarFilter == null,
        section: 1,
        keepsOpen: true,
      ),
    ];
    var section = 1;
    for (final group in current.activeGroups) {
      section++;
      final title = _groupLabel(ref, group);
      final filter = current.calendarFilter;
      for (final src in group.calendars) {
        ids.add(src.id);
        options.add(
          NativeMenuOption(
            src.name,
            // A waste calendar's entries wear their bins' colours, so the
            // calendar itself is a glyph rather than one more dot — the
            // recycling arrows, matching `AppIcons.recycle` on the Flutter
            // side of this same menu. **Not SF Symbols' `trash`**: that is the
            // delete can, and it sat in a list of calendars looking like an
            // offer to throw one away. `arrow.3.trianglepath` is the
            // recycling mark and has been there since 2019, well under the
            // 15.0 floor.
            symbol: src.isAbfall ? 'arrow.3.trianglepath' : null,
            color: src.isAbfall ? null : src.color,
            section: section,
            sectionTitle: title,
            selected: filter == null || filter.contains(src.id),
            keepsOpen: true,
          ),
        );
      }
    }

    final picked = await showNativeMenu(
      options: options,
      anchor: anchor,
      cancelLabel: L.s.cancel,
      dark: AppColors.isDark,
      onKeptOpen: (index) {
        final id = ids[index];
        if (index == tasksRow) {
          notifier.toggleTasks();
        } else if (id == null) {
          notifier.toggleAllCalendars();
        } else {
          notifier.toggleCalendarAnywhere(id);
        }
        updateNativeMenuSelection(statesOf());
      },
    );
    // Every row keeps the menu up, so the only answer a system menu gives here
    // is "closed" — anything but null means it was the one that ran.
    if (picked != null) return;
    if (!context.mounted) return;

    pushDropdownRoute(
      context,
      _AllCalendarsPickerRoute(
        anchor: anchor,
        onToggle: (id) => notifier.toggleCalendarAnywhere(id),
        onAll: () => notifier.toggleAllCalendars(),
        onToggleTasks: () => notifier.toggleTasks(),
      ),
    );
  }

  /// The header's control height — the same as [_CalendarHeaderActions]'
  /// capsule on the other side, so the two read as one bar.
  static const _height = 40.0;

  /// Also the native button's gap between the word and the caret
  /// (`imagePadding` in GlassButtonPlatformView.swift), so the sizer below
  /// measures what UIKit draws.
  static const _gap = 7.0;

  /// The same tier as the link and + glyphs in [_CalendarHeaderActions], so
  /// the controls on both sides of the title draw their glyphs at one size.
  static const _caretSize = AppGlyph.button;

  /// How many calendar colours the button wears at most. Three: the count
  /// beside them says how many there really are, and every dot past the third
  /// is width taken off a title this control already sits close to.
  static const _maxDots = 3;

  /// One colour dot, and how far the next one sits inside it — about a third
  /// of it, the bite [WhoAvatars] takes out of a stack of household avatars.
  static const _dotSize = 11.0;
  static const _dotOverlap = 4.0;

  /// Tighter than a glass pill's usual 14, which is what keeps the widest this
  /// control gets — a two-digit count, [_maxDots] dots, the gaps and the caret
  /// — inside [_TitleRow._collapsedSideInset]. That inset is the room the
  /// collapsed title keeps clear on *both* sides, and widening one side alone
  /// is exactly what pushes a centred title off centre.
  static const _padding = EdgeInsets.symmetric(horizontal: 12);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = state.calendarFilter;
    final isAll = filter == null;
    final dots = _dotColors;
    // "Alle" is spelled out — no set of colours stands for "everything", and a
    // muted dot would only say "some". A selection counts itself and shows
    // whose; a selection of one is already named by its own colour.
    final word = isAll ? L.s.all : (filter.length > 1 ? '${filter.length}' : null);
    // The Heute pill's type ([FloatingGlassPill] on the nav row), so the two
    // floating glass controls on this screen read at one size.
    final wordStyle = AppText.rowTitle.copyWith(color: AppColors.ink);
    final caretColor = AppColors.inkTertiary;

    final body = SizedBox(
      height: _height,
      child: Padding(
        padding: _padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (word != null) Text(word, maxLines: 1, style: wordStyle),
            if (word != null && dots.isNotEmpty) const SizedBox(width: _gap),
            if (dots.isNotEmpty) _FilterDots(colors: dots),
            const SizedBox(width: _gap),
            AppIcon(AppIcons.caretDown, size: _caretSize, color: caretColor, flat: true),
          ],
        ),
      ),
    );

    if (nativeGlassActive(context)) {
      // **A real glass `UIButton`, like the link and + beside the title.** The
      // `GlassSurface` this was — the material with a Flutter row laid over it
      // — sat next to two real buttons and read as a different control. A
      // `UIButton` takes one image, which is why the dots travel *with* the
      // caret rather than beside it; see [NativeGlassDots].
      return NativeGlassButtons(
        buttons: [
          NativeGlassButton(
            icon: AppIcons.caretDown,
            iconTrailing: true,
            // The words the button no longer spends width on are still what a
            // screen reader is owed: a stack of colours names nothing out loud.
            label: isAll
                ? L.s.all
                : (filter.length == 1 ? (_pickedName ?? L.s.all) : L.s.calendarCount(filter.length)),
            title: word,
            titleStyle: wordStyle,
            dots: dots.isEmpty ? null : NativeGlassDots(colors: dots, size: _dotSize, overlap: _dotOverlap),
            // Baked rather than tinted, because the dots' own colours are in
            // the same image.
            glyphColor: dots.isEmpty ? null : caretColor,
            onTap: () => _openMenu(context, ref),
          ),
        ],
        // A plain button's tint is its glyph colour — the caret.
        tint: caretColor,
        iconSize: _caretSize,
        sizer: body,
      );
    }

    return GestureDetector(
      onTap: () => _openMenu(context, ref),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(_height / 2),
        // No forced `tint`: the Flutter approximation takes the default light
        // material, which keeps the chevron legible.
        blurSigma: 16,
        boxShadow: AppShadows.glassButton,
        child: body,
      ),
    );
  }

  /// The accessible name when the button shows only a dot.
  String? get _pickedName {
    final filter = state.calendarFilter;
    if (filter == null) return null;
    for (final src in state.calendars) {
      if (filter.contains(src.id)) return src.name;
    }
    return null;
  }
}

/// The overlapping colour dots on [_CalendarFilterButton] — the Flutter
/// drawing of them. On iOS it is only ever *measured*: UIKit draws the same
/// stack into the button's one image slot (see [NativeGlassDots]), and this is
/// what tells it how wide to make the box.
///
/// The ring is the one thing the two draw differently, and for a reason. Here
/// it is [AppColors.surface], the way [AvatarStack] separates two heads; on
/// glass the gap is *cleared* instead, so the material shows through it — a
/// solid ring on glass would read as a sticker laid on the button.
class _FilterDots extends StatelessWidget {
  final List<Color> colors;

  const _FilterDots({required this.colors});

  @override
  Widget build(BuildContext context) {
    const size = _CalendarFilterButton._dotSize;
    const step = size - _CalendarFilterButton._dotOverlap;
    return SizedBox(
      width: size + step * (colors.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.surface, blurRadius: 0, spreadRadius: 2)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The width every calendar dropdown panel shares.
const _menuWidth = 244.0;

// ---------------------------------------------------------------------------
// The chip's own calendar list
// ---------------------------------------------------------------------------

/// The popup that hangs off an account chip: its calendars, each tickable.
///
/// Distinct from [_AllCalendarsPickerRoute] in what it is for. That one can
/// cross accounts, and also stands in for the whole chip row once the header
/// has collapsed. This one belongs to one chip and refines what is
/// already showing inside that account, so it stays open while rows are ticked
/// — narrowing three calendars to two is one gesture, not two round trips
/// through a menu.
///
/// It uses a near-opaque material rather than a [GlassSurface]: UIKit's own
/// menus are a near-opaque vibrant material, and real glass over the month
/// grid let the day numbers read straight through the rows.
class _CalendarPickerRoute extends PopupRoute<void> with DropdownRoute<void> {
  /// The chip's rect in global coordinates.
  final Rect anchor;
  final CalendarGroup group;
  final void Function(String calendarId) onToggle;

  _CalendarPickerRoute({required this.anchor, required this.group, required this.onToggle});

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => L.s.close;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    final maxLeft = (size.width - _menuWidth - AppSpacing.screenPad).clamp(
      AppSpacing.screenPad,
      double.infinity,
    );
    return Stack(
      children: [
        Positioned(
          left: anchor.left.clamp(AppSpacing.screenPad, maxLeft),
          top: anchor.bottom + 6,
          child: _CalendarPickerSurface(group: group, onToggle: onToggle),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

/// The picker's panel. A [ConsumerWidget] rather than a plain one because the
/// route stays up while rows are ticked: it has to redraw its own checkmarks
/// from the filter it is changing.
class _CalendarPickerSurface extends ConsumerWidget {
  final CalendarGroup group;
  final void Function(String calendarId) onToggle;

  const _CalendarPickerSurface({required this.group, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(calendarProvider).calendarFilter;
    // No filter at all means every calendar is showing, including all of these.
    final shown = filter == null ? group.ids : filter.intersection(group.ids);

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: [...AppShadows.menu]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: _menuWidth,
              color: AppColors.menuSurface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The account's name as a caption over its calendars, so the
                  // panel says whose three these are once it has covered the
                  // chip it came out of.
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 6),
                    child: Text(_groupLabel(ref, group), style: AppText.microLabel),
                  ),
                  for (final src in group.calendars)
                    _CalendarPickerRow(
                      label: src.name,
                      color: src.color,
                      glyph: src.isAbfall ? AppIcons.recycle : null,
                      checked: shown.contains(src.id),
                      onTap: () => onToggle(src.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarPickerRow extends StatelessWidget {
  final String label;
  final Color color;
  final bool checked;
  final VoidCallback onTap;

  /// Drawn in place of the colour dot on the row standing for every calendar
  /// at once. Same reason as the chip's — see [_CalendarChip.glyph].
  final IconData? glyph;

  const _CalendarPickerRow({
    required this.label,
    required this.color,
    required this.checked,
    required this.onTap,
    this.glyph,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            if (glyph != null)
              SizedBox(
                width: 9,
                child: Center(child: AppIcon(glyph!, size: 16, color: AppColors.inkSecondary)),
              )
            else
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: checked ? AppText.itemTitle : AppText.input,
              ),
            ),
            // Drawn either way rather than only when ticked: an unticked row
            // with nothing on the right reads as a label, and the whole point
            // of this panel is that every row is a switch.
            //
            // Round and accent-blue, the shape a multiple-choice tick has on
            // iOS — and deliberately *not* the calendar's own colour, which is
            // already saying which calendar this is in the dot on the left. A
            // box that changed hue per row would read as a second piece of
            // information rather than as "on".
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? AppColors.accent : Colors.transparent,
                border: checked ? null : Border.all(color: AppColors.inkTertiary, width: 1.5),
              ),
              child: checked ? const AppIcon(AppIcons.check, size: 13, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The "Alle" chip's own list — the one filter that may cross accounts
// ---------------------------------------------------------------------------

/// The popup that hangs off the "Alle" chip: every calendar in the row,
/// grouped under the account it belongs to, each tickable.
///
/// The third of the three panels, and the only one that can express "Alice's
/// Klausurplan *and* Papa's work calendar". [_CalendarPickerRoute] refines
/// inside the single account whose chip it hangs off, so it cannot put two
/// people's
/// calendars on screen together and leave everything else off. That was the
/// gap: an account chip is a whole person, so two people meant no filter at
/// all. "Alle" is the chip that stands for nobody in particular, so the
/// selection that belongs to nobody in particular belongs to it.
///
/// Like [_CalendarPickerRoute] it stays up while rows are ticked — building a
/// selection out of six calendars is one gesture, not six round trips — and it
/// uses the same near-opaque material, for the reason recorded there.
class _AllCalendarsPickerRoute extends PopupRoute<void> with DropdownRoute<void> {
  /// The chip's rect in global coordinates.
  final Rect anchor;
  final void Function(String calendarId) onToggle;
  final VoidCallback onAll;

  /// Adds the to-do overlay row on top — given by the collapsed header's
  /// button, which stands in for the whole chip row, to-do chip included.
  final VoidCallback? onToggleTasks;

  _AllCalendarsPickerRoute({
    required this.anchor,
    required this.onToggle,
    required this.onAll,
    this.onToggleTasks,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => L.s.close;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final size = MediaQuery.sizeOf(context);
    final maxLeft = (size.width - _menuWidth - AppSpacing.screenPad).clamp(
      AppSpacing.screenPad,
      double.infinity,
    );
    final top = anchor.bottom + 6;
    return Stack(
      children: [
        Positioned(
          left: anchor.left.clamp(AppSpacing.screenPad, maxLeft),
          top: top,
          child: _AllCalendarsPickerSurface(
            // Every calendar of every account fits in no fixed height, so the
            // panel takes what is left below the chip and scrolls the rest.
            maxHeight: (size.height - top - AppSpacing.screenPad * 2).clamp(160.0, double.infinity),
            onToggle: onToggle,
            onAll: onAll,
            onToggleTasks: onToggleTasks,
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

/// The cross-account picker's panel. A [ConsumerWidget] for the same reason
/// [_CalendarPickerSurface] is one: the route stays up while rows are ticked,
/// so it redraws its own checkmarks from the filter it is changing.
class _AllCalendarsPickerSurface extends ConsumerWidget {
  final double maxHeight;
  final void Function(String calendarId) onToggle;
  final VoidCallback onAll;
  final VoidCallback? onToggleTasks;

  const _AllCalendarsPickerSurface({
    required this.maxHeight,
    required this.onToggle,
    required this.onAll,
    this.onToggleTasks,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final filter = state.calendarFilter;
    final groups = state.activeGroups;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), boxShadow: [...AppShadows.menu]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: _menuWidth,
              color: AppColors.menuSurface,
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (onToggleTasks != null) ...[
                      _CalendarPickerRow(
                        label: L.s.todosChip,
                        color: AppColors.muted,
                        glyph: AppIcons.checkCircle,
                        checked: state.showTasks,
                        onTap: onToggleTasks!,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Divider(height: 0.5, thickness: 0.5, color: AppColors.menuSeparator),
                      ),
                    ],
                    // A checkbox over every row below it: ticked, it clears
                    // them all; unticked, it is the way back to everything —
                    // including out of a selection emptied to nothing.
                    _CalendarPickerRow(
                      label: L.s.all,
                      color: AppColors.muted,
                      glyph: AppIcons.users,
                      checked: filter == null,
                      onTap: onAll,
                    ),
                    for (final group in groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Divider(height: 0.5, thickness: 0.5, color: AppColors.menuSeparator),
                      ),
                      // Whose calendars these are, over them — the same caption
                      // one account's own popup wears, repeated per account
                      // because this panel holds all of them at once.
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 6),
                        child: Text(_groupLabel(ref, group), style: AppText.microLabel),
                      ),
                      for (final src in group.calendars)
                        _CalendarPickerRow(
                          label: src.name,
                          color: src.color,
                          glyph: src.isAbfall ? AppIcons.recycle : null,
                          // No filter at all means every calendar is showing,
                          // this one included.
                          checked: filter == null || filter.contains(src.id),
                          onTap: () => onToggle(src.id),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
