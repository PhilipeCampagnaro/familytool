import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/icon_suggestions.dart';
import '../theme/tokens.dart';
import 'brand_mark.dart';
// IconImage lives beside [BrandMark] so the mark can draw one without
// importing this file back; every caller of the tile still gets it from here.
export 'icon_image.dart';
import 'icon_image.dart';
import 'anchored_menu.dart';
import 'app_sheet.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

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

  /// A photograph chosen on a sheet that has nothing to attach it to yet.
  ///
  /// Only the **new**-box case needs this. Every other picture is written the
  /// moment it is chosen, exactly as the profile picture is — but a box that
  /// does not exist has no id, and the object layout keys on that id, so the
  /// file waits here until the insert comes back. See `BoxNotifier.createBox`.
  String? photoFile;

  IconDraft(this.picked, {this.photoFile});
}

/// The icon in front of a list, a box or a row.
///
/// Three cases, and the difference between them is not decoration.
///
/// **A symbol glyph is drawn bare**, in the theme's own ink, at
/// [AppText.markBareGlyph] of the slot. It sat on an [AppPalette.surfaceAlt]
/// disc until 2026-09-16, on the reasoning that a hairline mark needs somewhere
/// to be — but a duotone glyph is not a hairline mark. Its under-layer is
/// already a mass behind the strokes, so the disc was a second ground under a
/// shape that brings its own, and in a column mixing glyphs with grocery
/// pictures it was also the only thing wearing one: every food row read as
/// artwork and every other row as a button. (The same discovery `GlyphTile`
/// made when the duotone set took its glass lens's job — see the glyph-tile
/// section of docs/design-system.md.)
///
/// **A grocery picture is drawn bare**, at nearly the full width of the slot.
/// It is a photograph on nothing — a Paprika, a Milchtüte — and it arrives
/// already sized and centred, so a disc around it only costs the inset. On dark
/// it keeps the white [AppPalette.brandTile] under it, because the art is drawn
/// for white paper; that is the rule the grocery rows in Listen follow too.
///
/// **A shop logo is [BrandMark]'s**, in every one of the tile's shapes — the
/// chip, the disc, the picker's grid — because a shop framed one way here and
/// another way in Ausgaben is the same logo drawn twice. The reasoning for the
/// white ground and the edge-to-edge fill lives there; [imageSize] does not
/// reach it.
///
/// A caller that names its own [background] is asking for the disc and gets it.
class IconTile extends StatelessWidget {
  final String? iconKey;
  final double size;

  /// A signed URL for a photograph the user took of this very thing, which
  /// **replaces** [iconKey] when it is there.
  ///
  /// It fills the disc edge to edge rather than sitting inside it like a logo,
  /// and that is the honest treatment: the two catalog cases are *art on a
  /// background*, drawn small and centred, whereas a photo of the drill in the
  /// cellar is a photo — cropping it to the circle is what makes the row read
  /// as "this is the thing" instead of "here is a picture of something".
  final String? photoUrl;

  /// A picture that is on **this** device already — the file the picker just
  /// handed over, before (or instead of) an upload. Drawn in preference to
  /// [photoUrl]: it needs no round trip, so the tile fills the instant the user
  /// chooses, and a new box's picture has somewhere to be shown while the box
  /// it belongs to does not exist yet.
  final String? photoFile;

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

  /// Overrides the fill the tile would pick for itself — [AppPalette.brandTile]
  /// for art, [AppPalette.surface] for a glyph.
  ///
  /// For the one case where the fill is carrying a *distinction* rather than
  /// making a picture readable: the event sheet draws what already hangs off the
  /// appointment on the ordinary grey disc and the two "…erstellen" rows on a
  /// white one, so the card of things and the card of actions are told apart
  /// before either label is read. Leave it null everywhere else — the automatic
  /// choice is about legibility (see the class doc) and second-guessing it is
  /// how a shop logo ends up unreadable on dark.
  final Color? background;

  final bool border;

  /// Puts the icon on the tile's own disc without naming a colour for it —
  /// [background] with the choosing left here, so a caller asking for the ground
  /// does not also have to know that a logo's is white and a glyph's is grey.
  ///
  /// **It marks a *place*, not a kind of icon: the disc belongs to a
  /// container's own name.** A list or a box wears it wherever it is named —
  /// its row on the overview, the header of it once open, the collapsed title
  /// above that — and the articles *inside* it do not, in any of the four
  /// kinds. A container is a heading and its contents are a column of rows, and
  /// giving every row of contents a disc turns that column into a strip of
  /// buttons — which is the shape the grocery photographs are deliberately
  /// drawn bare to avoid. The overview is the other case: there every row *is*
  /// a heading, so the disc marks them all and marks nothing out.
  ///
  /// **The fill is [AppPalette.surface], not [AppPalette.surfaceAlt]** — the
  /// card's own white on light, one step darker than the card on dark. It was
  /// the grey fill, which on a white card drew a second tone into a row that
  /// already has a title, a subtitle and a chevron in three greys of their own;
  /// what marks the container is the *ring*, and the ring is what stays. On the
  /// header, where the disc sits on [AppPalette.screenBg] rather than on a
  /// card, the white then reads as a lift off the page instead of blending into
  /// the grey behind it, which is the place the disc is doing the most work.
  final bool disc;

  const IconTile({
    super.key,
    required this.iconKey,
    required this.size,
    required this.imageSize,
    this.photoUrl,
    this.photoFile,
    this.glyphSize,
    this.fallbackIcon = AppIcons.listChecks,
    this.glyphColor,
    this.background,
    this.border = true,
    this.disc = false,
  });

  @override
  Widget build(BuildContext context) {
    final choice = resolveIcon(iconKey);
    final asset = choice?.asset;
    final hasPhoto = photoFile != null || photoUrl != null;
    // A named [background] is a disc asked for outright, so it answers this too.
    final wantsDisc = disc || background != null;
    // An emoji is the model's own picture, drawn as text — see
    // [emojiIconPrefix]. It follows the same rule as everything else here: bare
    // on a row, on the disc where the place wears one. A little under the
    // glyphs' own numbers, because an emoji fills its em box where a Phosphor
    // mark leaves air inside it; `height: 1` because the font's line spacing
    // would otherwise push it off the centre line.
    final emoji = choice?.emoji;
    if (emoji != null && !hasPhoto) {
      final mark = Text(
        emoji,
        style: TextStyle(fontSize: glyphSize ?? size * (wantsDisc ? 0.52 : 0.56), height: 1),
        textAlign: TextAlign.center,
      );
      if (!wantsDisc) {
        return SizedBox(
          width: size,
          height: size,
          child: Center(child: mark),
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? AppColors.surface,
          shape: BoxShape.circle,
          border: border ? Border.all(color: AppColors.hairline) : null,
        ),
        alignment: Alignment.center,
        child: mark,
      );
    }
    if (asset != null && !hasPhoto && !wantsDisc) {
      // A brand mark in its chip — see the class doc. The inset is what a logo
      // is normally given on a white card, and the clip is for the full-bleed
      // ones, which end at the chip's corners instead of squaring them off.
      if (choice?.kind == IconKind.merchant) {
        return BrandMark(size: size, asset: asset, border: border);
      }
      // A grocery picture, bare — but not on dark, where the white disc below
      // is what keeps art drawn for paper visible.
      if (!AppColors.isDark) {
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: IconImage(asset: asset, size: size * 0.88),
          ),
        );
      }
    }
    // The glyph, on nothing — including the fallback, which is a glyph that
    // happens to have been chosen by absence. Everything below this line needs a
    // ground for a reason: a photograph has to be cropped to *some* shape, art
    // drawn for paper needs white under it on dark, and a caller that named a
    // [background] is asking for the disc outright.
    if (!hasPhoto && asset == null && !wantsDisc) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: AppIcon(
            choice?.glyph ?? fallbackIcon,
            size: glyphSize ?? AppText.markBareGlyph(size),
            color: glyphColor ?? AppColors.inkSecondary,
          ),
        ),
      );
    }
    // A shop on the disc is a shop anywhere else — same frame, one widget.
    if (!hasPhoto && background == null && choice?.kind == IconKind.merchant && asset != null) {
      return BrandMark(size: size, asset: asset, border: border);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? (asset != null ? AppColors.brandTile : AppColors.surface),
        shape: BoxShape.circle,
        border: border ? Border.all(color: AppColors.hairline) : null,
      ),
      alignment: Alignment.center,
      clipBehavior: hasPhoto ? Clip.antiAlias : Clip.none,
      child: hasPhoto
          ? PhotoThumbnail(url: photoUrl, filePath: photoFile, size: size)
          : asset != null
          ? ClipOval(
              child: IconImage(asset: asset, size: imageSize),
            )
          : AppIcon(
              choice?.glyph ?? fallbackIcon,
              size: glyphSize ?? imageSize * 0.78,
              color: glyphColor ?? AppColors.inkSecondary,
            ),
    );
  }
}

/// A stored photograph, cropped square and sized for the tile it fills.
///
/// The URL is signed and expires (a week, re-signed on every load), so a
/// failure here is ordinary rather than exceptional — an expired link, a phone
/// with no signal, an object swept up on another device. Every one of them
/// resolves to the muted placeholder rather than to Flutter's grey exception
/// box, and the row around it carries on saying what the thing is called.
class PhotoThumbnail extends StatelessWidget {
  /// A signed URL from Storage. Used when there is no [filePath].
  final String? url;

  /// A file on this device. Preferred, because there is nothing to fetch.
  final String? filePath;

  final double size;

  const PhotoThumbnail({super.key, this.url, this.filePath, required this.size});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    // Decoded at the size it is drawn at. A 1600px photo decoded for a 44pt
    // circle is several megabytes of memory per row, and a box screen is a list
    // of them.
    final cache = (size * scale).round();
    final broken = _broken(size);

    final local = filePath;
    if (local != null) {
      return Image.file(
        File(local),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cache,
        // The device copy is gone (a reinstall moved the app container, or the
        // file was swept up) — fall through to the stored one rather than
        // showing a hole.
        errorBuilder: (context, _, _) => url == null
            ? broken
            : Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: cache,
                errorBuilder: (context, _, _) => broken,
              ),
      );
    }

    // Both empty is ordinary rather than exceptional: an attachment whose
    // signing failed and whose device copy is from a previous install has
    // neither, and it must still draw its row.
    final remote = url;
    if (remote == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: broken),
      );
    }

    return Image.network(
      remote,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: cache,
      errorBuilder: (context, _, _) => broken,
    );
  }

  /// An expired link, a phone with no signal, an object swept up on another
  /// device — all ordinary here, and all of them resolve to this rather than to
  /// Flutter's grey exception box. The row around it still says what the thing
  /// is called.
  Widget _broken(double size) => AppIcon(AppIcons.image, size: size * 0.45, color: AppColors.mutedLight);
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
/// **The row is about the symbol and nothing else**, even on a sheet that also
/// carries a photograph. "Ändern" goes straight into [showIconPicker] rather
/// than into a menu that asks symbol-or-photo first: two of that menu's four
/// rows were about a picture, so the commonest tap on the sheet — correct the
/// guessed symbol — cost an extra choice every time. The photograph is
/// [PhotoFieldRow]'s, on its own row underneath, and the symbol stays visible
/// while there is one: it is what the thing goes back to when the picture is
/// removed, and a tile showing the photo twice in adjacent rows says the same
/// thing twice while hiding the fallback.
///
/// [suggested] marks the icon as one the *name* produced rather than one the
/// user picked — the sparkle after the name says so, which is what makes the
/// automatic match legible instead of magic.
class IconFieldRow extends StatelessWidget {
  final String? iconKey;
  final bool suggested;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  const IconFieldRow({
    super.key,
    required this.iconKey,
    required this.onTap,
    this.suggested = false,
    this.fallbackIcon = AppIcons.listChecks,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final label = resolveIcon(iconKey)?.label;
    return _PictureFieldRow(
      onTap: onTap,
      leading: IconTile(
        iconKey: iconKey,
        size: 32,
        imageSize: 22,
        fallbackIcon: fallbackIcon,
        glyphColor: accent,
        border: false,
      ),
      label: label ?? L.s.symbol,
      trailing: L.s.change,
      badge: suggested && label != null ? AppIcon(AppIcons.sparkle, size: 13, color: accent) : null,
    );
  }
}

/// The photograph row, directly under [IconFieldRow] on the box and box-item
/// sheets: "Bild hochladen" while there is none, the picture and "Ändern" once
/// there is.
///
/// **One picture, and it stands in for the symbol** — that is the whole rule,
/// and it is the storage column's shape rather than a limit imposed here:
/// `boxes.photo_path` and `box_items.photo_path` hold one path, so a second
/// photograph of the same drill replaces the first. A list *article* is the
/// other case and keeps its attachment list, because a receipt and a manual
/// are not two attempts at the same picture.
///
/// The tap puts up [showPictureMenu] — Mediathek, Kamera, and "Foto entfernen"
/// once there is one to remove. Two system pickers cannot be collapsed into a
/// single tap, but the menu now asks one question instead of two.
class PhotoFieldRow extends StatelessWidget {
  /// A signed URL for a stored photograph — see [IconTile.photoUrl].
  final String? photoUrl;

  /// A picture that has not been uploaded yet — see [IconTile.photoFile]. This
  /// is what a *new* box's or item's photo is until the row exists to hang it
  /// on.
  final String? photoFile;

  /// Where the fallback dropdown hangs when there is no system action sheet to
  /// put up — see [showPictureMenu].
  final GlobalKey anchorKey;

  /// Marks the row as busy while a picture is on its way up, so a slow upload
  /// is a spinner rather than a row that looks like it ignored the tap.
  final bool uploading;

  final VoidCallback onTap;

  const PhotoFieldRow({
    super.key,
    required this.anchorKey,
    required this.onTap,
    this.photoUrl,
    this.photoFile,
    this.uploading = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hasPhoto = photoFile != null || photoUrl != null;
    return _PictureFieldRow(
      anchorKey: anchorKey,
      onTap: uploading ? null : onTap,
      leading: uploading
          ? SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                ),
              ),
            )
          : Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
              alignment: Alignment.center,
              clipBehavior: hasPhoto ? Clip.antiAlias : Clip.none,
              child: hasPhoto
                  ? PhotoThumbnail(url: photoUrl, filePath: photoFile, size: 32)
                  : AppIcon(AppIcons.image, size: 17, color: accent),
            ),
      // Named "Foto" only once there is one: the empty row is an invitation,
      // and a row reading "Foto" with no photograph on it is a label for
      // something that isn't there.
      label: hasPhoto ? L.s.photo : L.s.uploadImage,
      trailing: hasPhoto ? L.s.change : null,
    );
  }
}

/// The shape both picture rows share: a 32pt tile, a label that ellipsises
/// before it pushes anything off the row, and a chevron with an optional word
/// in front of it.
class _PictureFieldRow extends StatelessWidget {
  final Widget leading;
  final String label;
  final String? trailing;
  final Widget? badge;
  final GlobalKey? anchorKey;
  final VoidCallback? onTap;

  const _PictureFieldRow({
    required this.leading,
    required this.label,
    this.trailing,
    this.badge,
    this.anchorKey,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: anchorKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 11),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                  ),
                  if (badge != null) ...[const SizedBox(width: 6), badge!],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Text(trailing!, style: AppText.buttonSmall.copyWith(color: AppColors.muted)),
            ],
            const SizedBox(width: 4),
            AppIcon(AppIcons.caretRight, size: 16, color: AppColors.mutedLight),
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
                  AppIcon(AppIcons.magnifyingGlass, size: 17, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
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
            child: Text(title, style: AppText.groupHeading),
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
            Text(label, style: AppText.buttonSmall.copyWith(color: accent)),
            const SizedBox(width: 6),
            AppIcon(expanded ? AppIcons.caretUp : AppIcons.caretDown, size: 16, color: accent),
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
            if (selected) AppIcon(AppIcons.check, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

/// What a picture row's menu can produce.
///
/// **No symbol row.** It used to have one, and that is what made the box
/// sheet's "Ändern" a two-step job: the menu asked which *kind* of picture
/// before it asked anything useful, on a row whose commonest use is correcting
/// the guessed symbol. Symbols are [IconFieldRow]'s and photographs are
/// [PhotoFieldRow]'s, so each row's tap already knows the answer.
enum PictureChoice {
  /// The photo library.
  photo,

  /// Take one now.
  camera,

  /// Back to the symbol the name chose, and the object deleted.
  remove,
}

/// The menu behind the picture row on a create/edit sheet.
///
/// One of the menus that made [showAnchoredMenu] learn UIKit's: it opens from
/// *inside* a [showAppSheet], whose header carries native glass buttons, and
/// Flutter content composited after a platform view can be dropped whole on
/// device — the failure that already ate the Kalender event sheet's route menu,
/// which opened, swallowed the taps behind it and never painted. On iOS the
/// system presents this one, so there is no Flutter layer left to lose.
///
/// A completer rather than a return value because a menu answers by running the
/// picked row's callback. `showAnchoredMenu` waits for the menu to close first,
/// so a menu dismissed without a choice simply leaves the completer alone.
///
/// [hasPhoto] adds the destructive "Foto entfernen" — there is nothing to
/// remove until there is.
Future<PictureChoice?> showPictureMenu(
  BuildContext context, {
  required GlobalKey anchorKey,
  required bool hasPhoto,
}) async {
  final choices = [PictureChoice.photo, PictureChoice.camera, if (hasPhoto) PictureChoice.remove];
  final completer = Completer<PictureChoice?>();
  await showAnchoredMenu(
    context: context,
    anchorKey: anchorKey,
    items: [
      for (final c in choices)
        AnchoredMenuItem(
          label: switch (c) {
            PictureChoice.photo => L.s.photo,
            PictureChoice.camera => L.s.camera,
            PictureChoice.remove => L.s.removePhoto,
          },
          icon: switch (c) {
            PictureChoice.photo => AppIcons.image,
            PictureChoice.camera => AppIcons.camera,
            PictureChoice.remove => AppIcons.trash,
          },
          symbol: switch (c) {
            PictureChoice.photo => 'photo.on.rectangle',
            PictureChoice.camera => 'camera',
            PictureChoice.remove => 'trash',
          },
          destructive: c == PictureChoice.remove,
          onSelected: () => completer.complete(c),
        ),
    ],
  );
  if (!completer.isCompleted) completer.complete(null);
  return completer.future;
}
