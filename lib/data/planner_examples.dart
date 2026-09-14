library;

import '../l10n/l10n.dart';

/// **Which four suggestion chips Vorhaben offers today.**
///
/// The chips are not a menu of commands, they are the only place the feature
/// says what it can do — so their job is to show the *range*, and their second
/// job is to still be interesting on the tenth visit. Those two pull against
/// each other, and [plannerSuggestions] is where they are reconciled.
///
/// **One draw per group, never a draw from one pool.** `plannerExampleGroups`
/// keeps the examples in four buckets — Anlässe und Reisen, Einkauf und
/// Haushalt, Bauen und Garten, Kochen — and this takes exactly one from each,
/// in that order. Shuffling a flat list of twenty-four would every so often
/// deal four dinners, and a household that met Vorhaben on that day would learn
/// it was a recipe generator and never ask it for a Hochbeet. Stratifying costs
/// nothing and makes the bad hand impossible.
///
/// **A rotation, not a random number.** The index is the date, so the row is
/// the same all day and different tomorrow, and every example in a group comes
/// up before any of them comes up twice. Randomness would be worse in both
/// directions at once: it can repeat yesterday's chip, and it can hide one for
/// a month.
///
/// **The cycle is as long as the longest group, and no longer.** With four
/// groups of six the same four chips come round together every sixth day —
/// worth knowing, not worth engineering away, because the reader who notices
/// that Weihnachtsessen and Butter Chicken always arrive on the same morning
/// has been reading this row for a week. Give the groups different lengths and
/// the combinations stop lining up; that is the lever, if it ever matters.
///
/// **Pure, so the caller does not have to hold it.** Being a function of the
/// day alone means calling this in a `build` is safe — the chips cannot
/// reshuffle under a reader who is mid-sentence, which is the failure mode of
/// picking in `initState` *or* of shuffling inline. Nothing about it belongs in
/// `PlannerState`.
List<PlannerExample> plannerSuggestions(DateTime day) {
  final groups = L.s.plannerExampleGroups;
  final today = _epochDay(day);
  return [
    for (var i = 0; i < groups.length; i++)
      // The `+ i` phases the groups apart, so day zero is not "the first entry
      // of everything" and two groups of the same length do not present as a
      // single list read four abreast.
      groups[i][(today + i) % groups[i].length],
  ];
}

/// Days since the epoch, for a date that came out of `calToday()` and so is
/// local midnight. Rebuilt in UTC first: subtracting two local `DateTime`s
/// across a DST boundary yields 23 or 25 hours, and `inDays` would then hold
/// the same number for two different days.
int _epochDay(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
