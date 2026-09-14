import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// **The status island** — one line at the top of a screen that says the single
/// most pressing thing about what is below it, and nothing else.
///
/// Home fills the slot Kalender gives the month name with it ([DayIsland] in
/// `lib/screens/home/day_island.dart`); Ausgaben fills its own collapsing block
/// the same way (`lib/screens/spend/spend_island.dart`). Both build a ladder of
/// cases and hand the first match to an [IslandLine]; this file is the sentence
/// itself, the crossfade between two of them and the wave that says one has
/// just changed.
///
/// A row of counters would be a dashboard, and the tabs already are one. The
/// island is the sentence somebody would otherwise have gone looking for.

/// The crossfade between one sentence and the next.
///
/// **It belongs here rather than in the row that hosts the island.** A switcher
/// one level up compares the widget it is handed — always a keyless
/// `DayIsland`/`SpendIsland` — so it never sees one state become another and
/// every change lands as an instant swap. The keys are on what those build, so
/// the switcher has to be around them.
///
/// The two halves **do not overlap**: the interval curves spend the first half
/// of the animation taking the old sentence away and the second half bringing
/// the new one in. A plain crossfade of two different sentences at the same
/// left edge is two sentences printed over each other.
class StatusIsland extends StatelessWidget {
  /// The current line, keyed by which rung of the ladder it came from.
  final Widget child;

  const StatusIsland({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: const Interval(0.55, 1, curve: Curves.easeOutCubic),
      switchOutCurve: const Interval(0.55, 1, curve: Curves.easeIn),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The line itself: a glyph, a sentence, the sentence's subject underneath it,
/// and — in setup mode only — the count and the chevron that folds the
/// checklist out.
///
/// **The second line is what the first one is counting.** "Noch 1 offen" is a
/// number and an adjective; every other count in the app sits on a row, under a
/// section heading or beside an icon that says which of four kinds of thing it
/// means, and the island has none of those. It is [AppText.microLabel] in muted
/// ink so it explains without competing — the sentence above it is still the
/// thing being read.
///
/// **The glyph is ink, in every state, and there is no way to tint it.** Red on
/// the warning mark and green on the finished one were the two that looked
/// earned, and they were the two that read worst: a red triangle at the top of
/// Home is the shape every app uses for *something went wrong*, so a household
/// with one late to-do saw an app reporting a fault. The sentence beside it
/// already says which of the seven things this is, and the reader is looking at
/// the sentence. So the colour is gone rather than parameterised — a knob for
/// it is an invitation to put the red back.
///
/// A caret belongs here only when the line answers a tap. The disclosure one
/// folds a checklist out below ([expanded]); [navigates] is the right-pointing
/// one, for a line whose tap leaves the screen — Listen's Vorhaben invitation.
/// On a line that only says something, a caret would promise a screen that does
/// not exist, so neither is the default.
class IslandLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final String? trailingLabel;
  final VoidCallback? onTap;

  /// Non-null only in setup mode, where the line is a disclosure control.
  final bool? expanded;

  /// Whether the tap goes somewhere else, which earns a right-pointing caret
  /// after the label. Only meaningful with [onTap], and never together with
  /// [expanded] — the same line cannot both open here and leave.
  final bool navigates;

  /// How the wave behaves on this line — see [IslandSweep].
  final IslandSweep sweep;

  const IslandLine({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    this.trailingLabel,
    this.onTap,
    this.expanded,
    this.navigates = false,
    this.sweep = IslandSweep.once,
  }) : assert(!(navigates && expanded != null));

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // No padding of its own: the two lines are a little under the row's
      // height and the row centres them, which keeps the sentence on roughly
      // the baseline the plain label sits on.
      child: _Sweep(
        trigger: '$label|$hint',
        mode: sweep,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 21, color: AppColors.inkSecondary),
            const SizedBox(width: 8),
            // Bounded so a long appointment name shortens instead of running
            // under the profile avatar.
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.sectionHeading,
                        ),
                      ),
                      if (trailingLabel case final count?) ...[
                        const SizedBox(width: 8),
                        Text(count, style: AppText.microLabel.copyWith(color: AppColors.muted)),
                      ],
                      if (navigates) ...[
                        const SizedBox(width: 6),
                        AppIcon(AppIcons.caretRight, size: 14, color: AppColors.mutedLight, flat: true),
                      ],
                      if (expanded case final open?) ...[
                        const SizedBox(width: 2),
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: AppIcon(AppIcons.caretDown, size: 15, color: AppColors.muted, flat: true),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.microLabel.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the wave does on a given line.
///
/// [IslandSweep.none] is for a sentence the reader changed themselves — tapping along the
/// day strip is not news, and a wave on every tap would be. [IslandSweep.loop] is the
/// loading line, where the wave is the spinner. [IslandSweep.once] is everything else: the
/// sentence changed while nobody was looking.
enum IslandSweep { none, once, loop }

/// One pale wave crossing the words, left to right, when the sentence lands.
///
/// **It plays once and then gets out of the way.** A line that shimmers for
/// ever is a loading state, and this line is never loading — it is the answer.
/// The sweep exists because the island's sentence changes while nobody is
/// looking at it: a to-do gets ticked somewhere else and the words are simply
/// different the next time the eye passes. The wave is what says *this changed*
/// without the header moving or flashing.
///
/// The highlight is the page's own colour rather than white, so the letters
/// dissolve towards the paper behind them as the wave passes and the effect
/// reads the same way on the dark palette, where white would be a flashbulb.
/// [BlendMode.srcATop] keeps it inside the glyphs, so it is the words that
/// wash rather than a band sliding over the header.
///
/// The shader is dropped entirely once the wave is done — a [ShaderMask] left
/// in place would put a save-layer under the header for the rest of the day.
class _Sweep extends StatefulWidget {
  final Widget child;

  /// What is being said. The sweep re-runs when this changes, which covers the
  /// case the switcher above cannot see: the same state with a new number, as
  /// "Noch 2 offen" becomes "Noch 1 offen".
  final String trigger;

  final IslandSweep mode;

  const _Sweep({required this.child, required this.trigger, this.mode = IslandSweep.once});

  @override
  State<_Sweep> createState() => _SweepState();
}

class _SweepState extends State<_Sweep> with SingleTickerProviderStateMixin {
  /// Slow enough that somebody who looks up mid-sweep still sees it travelling
  /// rather than catching the end of it. It was half this and read as a flicker
  /// — the wave has to be visibly on its way somewhere to say that the sentence
  /// under it is new.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _run() {
    switch (widget.mode) {
      case IslandSweep.none:
        _wave.value = 1;
      case IslandSweep.once:
        _wave.forward(from: 0);
      case IslandSweep.loop:
        _wave.repeat();
    }
  }

  @override
  void didUpdateWidget(_Sweep old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger || old.mode != widget.mode) _run();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  /// How much of the line the pale band covers at once. Wide enough that the
  /// wave has an edge on both sides of a short sentence.
  static const _band = 0.4;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wave,
      child: widget.child,
      builder: (context, child) {
        if (_wave.isCompleted) return child!;
        // Starts a band's width off the left edge and ends one off the right,
        // so the sentence is clean at both ends of the animation.
        final centre = -_band + Curves.easeInOut.transform(_wave.value) * (1 + _band * 2);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.transparent, AppColors.surface.withValues(alpha: .85), Colors.transparent],
            stops: [
              (centre - _band).clamp(0.0, 1.0),
              centre.clamp(0.0, 1.0),
              (centre + _band).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}
