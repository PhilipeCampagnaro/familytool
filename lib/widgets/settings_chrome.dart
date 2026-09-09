import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'action_bar.dart';
import 'app_sheet.dart';
import 'collapsing_header.dart';
import 'glass.dart';
import 'glyph_tile.dart';
import '../l10n/l10n.dart';
import '../theme/app_icons.dart';

/// The chrome every Settings sub-page is built from — the collapsing header and
/// hero card, the row, the field box, the divider rules.
///
/// Lifted out of settings_screen.dart when the calendar-connection pages needed
/// the same shell. Keeping one copy is the point: a second page that hand-rolls
/// its own row is how two screens in one settings tree start disagreeing about
/// padding, divider insets and where the chevron sits.

/// Chrome shared by every Settings sub-page: the same frosted collapsing
/// header as the root, with a [HeroCard] as the collapsing content and the
/// page's own [title] taking over the pinned bar once that card scrolls away.
class SettingsDetailPage extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  /// The page you came *from*, shown centred in the nav bar at rest — the back
  /// chevron beside it says where it goes, this says where. Defaults to the
  /// Settings root, which is where all but the provider pages are pushed from.
  /// Null means "Einstellungen" / "Settings" — resolved at build rather than
  /// defaulted, because a default parameter value can't hold an `L.s` string.
  final String? parentTitle;

  /// First-frame guess at the hero's height; re-measured immediately.
  final double estimatedHeroHeight;

  /// Something else in the masthead's glyph slot — see [HeroCard.leading]. Null
  /// keeps the [icon] on its glass tile, which is what all but one page wants.
  final Widget? leading;

  /// The page's primary action — pass the [AccentAction] rather than putting it
  /// in [children], and it is pinned to the bottom edge with the list scrolling
  /// underneath it. See [SettingsActionBar] for why it is worth the pin.
  final Widget? bottomAction;

  const SettingsDetailPage({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
    this.parentTitle,
    this.estimatedHeroHeight = 200,
    this.leading,
    this.bottomAction,
  });

  @override
  State<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<SettingsDetailPage> {
  @override
  Widget build(BuildContext context) {
    // The layout goes *inside* the Scaffold, not around it: the pinned bar has
    // to be under a Material or its label renders in the debug text style —
    // yellow, double-underlined — since nothing else on the route supplies one.
    // The `SafeArea` stays inside the body builder rather than around the
    // layout, so it takes the top inset off the header without also taking the
    // home-indicator inset away from the bar, which needs to carry it itself.
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: PinnedActionLayout(
        action: widget.bottomAction,
        bodyBuilder: (context, bottomInset) => SafeArea(
          bottom: false,
          child: CollapsingHeaderScreen(
            // At rest the bar names the page *behind* this one — the hero card
            // below is already saying where you are, and the chevron beside it
            // needs a label. Once the card scrolls out of sight the bar takes
            // this page's own title over, so the name is never missing, just
            // never duplicated. Both ends are nav-bar sized: there's no large
            // heading here to collapse, only a crossfade between two 17pt labels.
            titleRowBuilder: (context, t) => CollapsingScreenTitle(
              title: widget.parentTitle ?? L.s.settingsTitle,
              collapsedTitle: widget.title,
              t: t,
              expandedAlignment: Alignment.center,
              expandedFontSize: 17,
              leading: GlassIconButton(icon: AppIcons.caretLeft, onTap: () => Navigator.of(context).pop()),
              leadingWidth: 48,
              trailing: CloseSettingsButton(),
              trailingWidth: 48,
            ),
            estimatedExtraHeight: widget.estimatedHeroHeight,
            extraPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            extra: HeroCard(
              icon: widget.icon,
              title: widget.title,
              description: widget.description,
              leading: widget.leading,
            ),
            body: ScreenBodyPanel(
              child: ListView(
                // 40 is where a page without an action ends; with one, the
                // last card clears the bar by a block's gap.
                padding: EdgeInsets.fromLTRB(16, 18, 16, bottomInset == 0 ? 40 : bottomInset + AppSpacing.blockGap),
                children: widget.children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The X in a sub-page's header: leaves Settings entirely rather than stepping
/// back one page at a time, which is what the back chevron beside it is for.
class CloseSettingsButton extends StatelessWidget {
  const CloseSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(icon: AppIcons.x, onTap: () => Navigator.of(context).popUntil((r) => r.isFirst));
  }
}

/// The masthead every Settings sub-page opens with: the page's glyph on a
/// [GlyphTile], its title, and one sentence explaining what the page
/// changes. It replaces the
/// nav-bar title on those pages, which is why the pinned row above it is empty
/// until this scrolls away.
///
/// A card's geometry with none of a card's material: the same 20/22 insets a
/// [SectionCard] would give it, on the plain white header, with no fill, border
/// or shadow. The spacing is what the card was buying — drawing it as well only
/// added a rectangle you could barely see, whose height moved with each page's
/// description.
///
/// Keep the [SizedBox]: the header's `extra` slot is laid out loose inside a
/// centring Column, so a shrink-wrapping child drifts to the middle — which is
/// why this block used to look left-aligned on pages with a long description
/// and centred on pages with a short one ("Google Kalender verbinden.").
class HeroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  /// Drawn in place of the tiled [icon], at the same 52pt so the masthead keeps
  /// its measure whichever it is.
  ///
  /// One page uses it: Familienmitglieder, whose glyph is the household's own
  /// picture. The picture *is* the page's subject, so a second card underneath
  /// saying "tap to change the family picture" was the same thing twice — the
  /// masthead is where a page's identity already lives, and an editable one only
  /// needs to look editable.
  final Widget? leading;

  const HeroCard({super.key, required this.icon, required this.title, required this.description, this.leading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The same lens the rows below it wear, at masthead size — a bare
            // glyph up here and a tiled one in every row read as two systems.
            leading ?? GlyphTile(icon: icon, size: 52),
            const SizedBox(height: 16),
            Text(title, style: AppText.screenTitle),
            const SizedBox(height: 8),
            Text(description, style: AppText.body.copyWith(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// A single settings row: an icon tile (or custom [leading]), title +
/// optional subtitle, then — before the chevron — a gray [value], an
/// arbitrary [accessory] widget, or a [trailing] widget that replaces the
/// chevron outright (a `Switch`, say).
class SettingsRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;

  /// Right-aligned status text, e.g. "Nicht verbunden" or the current
  /// language.
  final String? value;

  /// Sits where [value] would, for non-text status (the family avatar stack).
  final Widget? accessory;

  /// Replaces value/accessory *and* the chevron — for rows that act in place.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// False greys the row out and takes its tap away — for an action that has
  /// already been done rather than one that is unavailable for now.
  ///
  /// **Greyed rather than hidden**, the same rule the sheet's save button
  /// follows: a row that disappears is a puzzle, a grey one is an answer. The
  /// chevron goes with the tap, so the row stops looking like a destination as
  /// well as ceasing to be one, and [value] is where the reason goes — a grey
  /// row with nothing to say is the version people file bugs about.
  final bool enabled;

  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.value,
    this.accessory,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // Held once: the chevron is drawn off the *effective* tap, so a disabled
    // row loses the arrow along with the gesture.
    final tap = enabled ? onTap : null;

    return GestureDetector(
      onTap: tap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        // The whole row together — the tile, the title and the reason — so it
        // recedes as one thing. Fading only the text would leave a fully
        // saturated disc in front of a grey label.
        opacity: enabled ? 1 : .45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              // A row with neither an icon nor a custom leading (the language
              // list) drops the slot entirely instead of indenting past an
              // empty one.
              if (leading case final leadingWidget?)
                leadingWidget
              else if (icon != null)
                // A circle, not a squircle: the rows that carry a *logo* (the
                // calendar providers, the family avatars) can only be round, and
                // a settings list that mixes both shapes reads as two lists.
                GlyphTile(icon: icon!),
              if (leading != null || icon != null) const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                    if (subtitle != null) Text(subtitle!, style: AppText.label),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else ...[
                ?accessory,
                if (value != null) Text(value!, style: AppText.label),
                if (tap != null) ...[
                  const SizedBox(width: 8),
                  AppIcon(AppIcons.caretRight, size: 16, color: AppColors.mutedLight),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled block inside a card — caption, optional hint, then the control.
/// Used by the profile form, where each setting needs a name that a plain
/// [SettingsRow] has nowhere to put.
///
/// With no [child] it is the card's own **heading**: the same caption and the
/// one line explaining what the card is for, as the first block above the rows.
/// That is why the Settings pages carry no headings *outside* their cards any
/// more — a caption floating above a card and a caption inside it are two
/// systems, and the floating one never lined up with the card's own text.
class FieldGroup extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget? child;

  const FieldGroup({super.key, required this.label, this.hint, this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // A heading has nothing under it to breathe away from, so it keeps the
      // symmetric inset instead of a field's roomier bottom.
      padding: EdgeInsets.fromLTRB(18, 18, 18, child == null ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.sectionHeading),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: AppText.body.copyWith(color: AppColors.muted)),
          ],
          if (child case final field?) ...[const SizedBox(height: 12), field],
        ],
      ),
    );
  }
}

/// The rounded outline every editable/selectable field in the profile form
/// sits in, so a text input and a read-only value read as the same control.
class FieldBox extends StatelessWidget {
  final Widget child;

  const FieldBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.iconTile),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: child,
    );
  }
}

/// Full-width action sitting *outside* a [SectionCard] — the family page's
/// "Mitglied einladen", the connect pages' "Verbinden". An action, not another
/// list row, so it gets the app's accent glass pill rather than a bordered box
/// that reads like one more white card.
class AccentAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AccentAction({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassAccentButton(
      icon: icon,
      label: label,
      onTap: onTap,
      expand: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    );
  }
}

/// A muted line of explanation on a Settings page, *outside* any card — the
/// footer under an action, in the iOS sense. Inset to the same 18 as a card's
/// own text so the page reads as one column rather than two.
///
/// Pass `inset: 0` inside a sheet: the sheet's gray body already carries that
/// 18, and a note that adds its own lands a step to the right of everything
/// around it.
class SettingsNote extends StatelessWidget {
  final String text;
  final double inset;

  const SettingsNote(this.text, {super.key, this.inset = 18});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Text(text, style: AppText.body.copyWith(color: AppColors.muted)),
    );
  }
}

/// The small caption naming the card under it — "Verbunden" over the list of
/// connected calendars.
///
/// Not a [FieldGroup] heading inside the card: a *field* needs its label in the
/// card because the label and the control are one thing, but a list of rows that
/// already say what they are needs only a quiet name over the group, and
/// `sectionHeading` at 16pt ink shouts it. Same 18 inset as a card's own text,
/// which is what the old caption at 6 never lined up with.
class GroupLabel extends StatelessWidget {
  final String label;

  const GroupLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Text(label, style: AppText.groupHeading),
    );
  }
}
