import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/icon_suggestions.dart';
import '../theme/tokens.dart';
import 'app_sheet.dart';
import '../l10n/l10n.dart';

/// The one place an icon is *drawn* and the one place an icon is *chosen*.
///
/// Both sides speak the same string — the `iconKey` from
/// `data/icon_suggestions.dart`, either an `assets/` path or `lucide:<name>` —
/// so a list, a box and an item can carry a shop logo, a grocery picture or a
/// Lucide glyph in a single nullable field.

/// An icon the user picked by hand, or `null` while the name is still choosing
/// for itself.
///
/// Mutable and passed around by reference on purpose: a create/edit sheet's
/// body owns the picker, but the save button belongs to the shared sheet chrome
/// ([showAppSheet]) and is handed its callback before the body exists. This is
/// the one object both of them hold.
class IconDraft {
  String? picked;

  IconDraft(this.picked);
}

/// The round icon in front of a list, a box or a row.
///
/// Three cases, and the difference between them is not decoration: a shop logo
/// or a grocery picture is **full-colour art drawn for a light background**, so
/// it gets the white [AppPalette.brandTile] disc in both palettes (same rule as
/// the calendar provider marks — several go unreadable on a dark circle). A
/// Lucide glyph is line art that takes the theme's own colour, so it sits on
/// the ordinary [AppPalette.surfaceAlt] fill.
class IconTile extends StatelessWidget {
  final String? iconKey;
  final double size;

  /// Edge length of the picture inside the disc. A glyph is drawn at
  /// [glyphSize], which defaults to a little under it — outline icons need the
  /// air a logo doesn't.
  final double imageSize;
  final double? glyphSize;

  /// Drawn when [iconKey] is null or names something the catalogs no longer
  /// have.
  final IconData fallbackIcon;

  /// Colour of a Lucide glyph (the fallback included); defaults to the muted
  /// ink a logo would sit at.
  final Color? glyphColor;

  final bool border;

  const IconTile({
    super.key,
    required this.iconKey,
    required this.size,
    required this.imageSize,
    this.glyphSize,
    this.fallbackIcon = LucideIcons.clipboardCheck,
    this.glyphColor,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final choice = resolveIcon(iconKey);
    final asset = choice?.asset;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: asset != null ? AppColors.brandTile : AppColors.surfaceAlt,
        shape: BoxShape.circle,
        border: border ? Border.all(color: AppColors.hairline) : null,
      ),
      alignment: Alignment.center,
      child: asset != null
          ? ClipOval(child: IconImage(asset: asset, size: imageSize))
          : Icon(
              choice?.glyph ?? fallbackIcon,
              size: glyphSize ?? imageSize * 0.78,
              color: glyphColor ?? AppColors.inkSecondary,
            ),
    );
  }
}

/// An icon asset at a bounded decode size. The shop logos are full-size
/// downloads and the picker puts 160 of them on screen at once; without
/// `cacheWidth` every one of them is decoded at its native resolution.
class IconImage extends StatelessWidget {
  final String asset;
  final double size;

  const IconImage({super.key, required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: (size * scale).round(),
      // A logo that was deleted from `assets/` shouldn't take the row with it.
      errorBuilder: (context, _, _) => Icon(LucideIcons.image, size: size * 0.8, color: AppColors.mutedLight),
    );
  }
}

/// The symbol row on a create/edit sheet: the icon as it stands, what it is
/// called, and "Ändern" with a chevron into [showIconPicker].
///
/// The name of the icon *is* the row's label — the generic word "Symbol" only
/// repeated what the picture next to it already said, and left the one piece of
/// information that changes ("Einkaufswagen") over on the right where a value
/// normally is. "Symbol" survives as the fallback for the seconds before the
/// typed name has matched anything, when there is no icon to name yet.
///
/// [suggested] marks the icon as one the *name* produced rather than one the
/// user picked — the sparkle after the name says so, which is what makes the
/// automatic match legible instead of magic.
class IconFieldRow extends StatelessWidget {
  final String? iconKey;
  final bool suggested;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  const IconFieldRow({super.key, required this.iconKey, required this.onTap, this.suggested = false, this.fallbackIcon = LucideIcons.clipboardCheck});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final label = resolveIcon(iconKey)?.label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconTile(iconKey: iconKey, size: 32, imageSize: 22, fallbackIcon: fallbackIcon, glyphColor: accent, border: false),
            const SizedBox(width: 11),
            // The name takes all the room the action leaves, so a long one
            // ellipsises instead of pushing "Ändern" off the row.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label ?? L.s.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle,
                    ),
                  ),
                  if (suggested && label != null) ...[
                    const SizedBox(width: 6),
                    Icon(LucideIcons.sparkles, size: 13, color: accent),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              L.s.change,
              style: AppText.buttonSmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mutedLight),
          ],
        ),
      ),
    );
  }
}

/// The manual override: pick a symbol, a shop logo or a grocery picture by
/// hand. Resolves to the chosen `iconKey`, or `null` if the sheet was closed
/// without choosing.
///
/// [name] is whatever has been typed into the name field, so the sheet opens on
/// the same suggestion the row behind it is already showing — the picker is
/// there to *correct* the automatic match, and starting somewhere unrelated
/// would make that a two-step job.
/// [subject] is what is being named — see [IconSubject]. It narrows the sheet to
/// the catalogs that subject may use, browsing and search alike: a box's picker
/// is symbols only, so it can't be given by hand the shop logo its automatic
/// match would never have offered.
Future<String?> showIconPicker(
  BuildContext context, {
  String? selected,
  String name = '',
  IconSubject subject = IconSubject.article,
}) {
  return showAppSheet<String>(
    context: context,
    // A tap on an icon *is* the save, so the header carries no check — see
    // [SheetPickerHeader].
    header: SheetPickerHeader(title: L.s.chooseSymbol),
    child: _IconPickerBody(selected: selected, name: name, subject: subject),
  );
}

class _IconPickerBody extends StatefulWidget {
  final String? selected;
  final String name;
  final IconSubject subject;

  const _IconPickerBody({required this.selected, required this.name, required this.subject});

  @override
  State<_IconPickerBody> createState() => _IconPickerBodyState();
}

class _IconPickerBodyState extends State<_IconPickerBody> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _choose(IconChoice choice) => Navigator.of(context).pop(choice.key);

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    final suggestion = query.isEmpty ? suggestIcon(widget.name, subject: widget.subject) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
              child: Row(
                children: [
                  Icon(LucideIcons.search, size: 17, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: AppText.searchInput,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: L.s.searchSymbolOrShop,
                        hintStyle: AppText.searchInput.copyWith(color: AppColors.muted),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (query.isNotEmpty)
          _Section(
            title: L.s.matches,
            choices: searchIcons(query, subject: widget.subject),
            selected: widget.selected,
            onSelect: _choose,
            emptyMessage: L.s.nothingFoundFor(query),
          )
        else ...[
          if (suggestion != null)
            _Section(
              title: L.s.suggestionFromName,
              choices: [suggestion],
              selected: widget.selected,
              onSelect: _choose,
            ),
          for (final group in symbolGroups)
            _Section(
              title: group.label,
              choices: [for (final icon in group.icons) icon.choice],
              selected: widget.selected,
              onSelect: _choose,
            ),
          if (widget.subject.allowsMerchants) _MerchantSection(selected: widget.selected, onSelect: _choose),
        ],
      ],
    );
  }
}

/// One heading over one [SectionCard] of [_IconRow]s — the same card-of-rows
/// the list overview and the search results are built from.
///
/// It used to be a `Wrap` of 74pt tiles, which is where the picker went wrong:
/// a symbol's German name is the thing you are actually reading ("Einkaufskorb",
/// "Einkaufstasche"), and under a tile that name had two 10.5pt lines and an
/// ellipsis to live in. A row gives it the whole width at the list's own type
/// size, and the icon keeps the identical [IconTile] it will have once picked —
/// so the picker previews the row it is choosing for.
class _Section extends StatelessWidget {
  final String title;
  final List<IconChoice> choices;
  final String? selected;
  final ValueChanged<IconChoice> onSelect;
  final String? emptyMessage;

  /// Appended inside the card, under the last row — the merchants section's
  /// "alle anzeigen" row.
  final Widget? footer;

  const _Section({
    required this.title,
    required this.choices,
    required this.selected,
    required this.onSelect,
    this.emptyMessage,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    if (choices.isEmpty && emptyMessage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 9),
            child: Text(
              title,
              style: AppText.groupHeading,
            ),
          ),
          if (choices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(emptyMessage!, style: AppText.label),
            )
          else
            SectionCard(
              children: dividedRows([
                for (final choice in choices)
                  _IconRow(choice: choice, selected: choice.key == selected, onTap: () => onSelect(choice)),
                ?footer,
              ]),
            ),
        ],
      ),
    );
  }
}

/// The shops, capped until asked for. There are ~170 logos: as tiles they were
/// a wall you scrolled past, and as rows the whole list would be most of the
/// sheet. The first [_shown] are there to be recognised, search covers the rest,
/// and the tail row opens the lot for anyone who would rather scroll.
class _MerchantSection extends StatefulWidget {
  final String? selected;
  final ValueChanged<IconChoice> onSelect;

  const _MerchantSection({required this.selected, required this.onSelect});

  @override
  State<_MerchantSection> createState() => _MerchantSectionState();
}

class _MerchantSectionState extends State<_MerchantSection> {
  static const _shown = 12;

  late final List<IconChoice> _all = merchantChoices;

  /// Open from the start when the icon already in use is one of the hidden
  /// ones — a picker that doesn't show you your own choice is a picker that
  /// looks like it lost it.
  late bool _expanded = _all.indexWhere((c) => c.key == widget.selected) >= _shown;

  @override
  Widget build(BuildContext context) {
    final hidden = _all.length - _shown;
    final visible = _expanded ? _all : _all.take(_shown).toList();
    return _Section(
      title: L.s.shops,
      choices: visible,
      selected: widget.selected,
      onSelect: widget.onSelect,
      footer: hidden <= 0
          ? null
          : _MoreRow(
              label: _expanded ? L.s.showLess : L.s.allMoreShops(hidden),
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
    );
  }
}

/// The card's last row when there is more behind it.
class _MoreRow extends StatelessWidget {
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  const _MoreRow({required this.label, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: AppText.buttonSmall.copyWith(color: accent),
            ),
            const SizedBox(width: 6),
            Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 16, color: accent),
          ],
        ),
      ),
    );
  }
}

/// One choosable icon as a card row: the picture, its German name, and a check
/// once it is the one in use.
class _IconRow extends StatelessWidget {
  final IconChoice choice;
  final bool selected;
  final VoidCallback onTap;

  const _IconRow({required this.choice, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        // A wash rather than a border: the row's edges belong to the card, and
        // an inset outline inside it reads as a second, misaligned card.
        color: selected ? accent.withValues(alpha: 0.07) : null,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 15),
        child: Row(
          children: [
            IconTile(iconKey: choice.key, size: 38, imageSize: 26, glyphColor: selected ? accent : null),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                choice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (selected ? AppText.itemTitle : AppText.rowTitle).copyWith(
                  color: selected ? accent : AppColors.ink,
                ),
              ),
            ),
            if (selected) Icon(LucideIcons.check, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}
