import 'package:flutter/material.dart';

import '../data/abfall_bins.dart';
import '../l10n/l10n.dart';
import '../models/calendar_connection.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'glyph_tile.dart';
import 'settings_chrome.dart';

/// "Restmüll — wie oft geleert?" and one chip per rhythm the address has, for
/// every bin the vendor makes the household name ([RhythmChoice]). The same
/// question the city's own calendar asks, answered off the bin sticker; the
/// connect sheet and the onboarding's address card both ask it with this.
///
/// Stateless: [picked] is bin to option id, and a tap reports the bin and the
/// option through [onPick] for the owner to store.
class RhythmPicker extends StatelessWidget {
  final List<RhythmChoice> choices;
  final Map<String, String> picked;
  final void Function(String bin, String option) onPick;

  const RhythmPicker({super.key, required this.choices, required this.picked, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final choice in choices)
          FieldGroup(
            // The bin itself, in its colour, so "Restabfall" and "Papierabfall"
            // are told apart at a glance — the way the cities' own forms do it.
            leading: GlyphTile(
              icon: binIconFor(choice.bin) ?? AppIcons.trash,
              tone: binColorFor(choice.bin) ?? AppColors.muted,
              size: 28,
            ),
            label: L.s.rhythmQuestion(choice.bin),
            hint: L.s.rhythmHint,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in choice.options)
                  AnswerChip(
                    label: rhythmOptionLabel(option),
                    selected: picked[choice.bin] == option.id,
                    onTap: () => onPick(choice.bin, option.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The vendor's words, and — where they name no rhythm ("Grau", "Rote Woche",
/// "Großmüllbehälter 1100 L") — how far apart the dates really fall.
String rhythmOptionLabel(RhythmOption option) {
  final every = option.every;
  if (every == null || RegExp(r'wöchentl|täglich', caseSensitive: false).hasMatch(option.id)) return option.id;
  return '${option.id} · ${every == 7 ? L.s.rhythmWeekly : L.s.rhythmEveryWeeks(every ~/ 7)}';
}

/// One answer to a question the waste vendor asks — a rhythm here, a house off
/// the vendor's list in the onboarding. Outlined, and filled with the accent
/// once picked.
class AnswerChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AnswerChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.iconTile),
          border: Border.all(color: selected ? accent : AppColors.hairline2),
        ),
        child: Text(label, style: AppText.body.copyWith(color: selected ? accent : AppColors.ink)),
      ),
    );
  }
}
