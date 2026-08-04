import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'app_sheet.dart';
import 'collapsing_header.dart';
import 'glass.dart';

/// The chrome every Settings sub-page is built from — the collapsing header and
/// hero card, the row, the field box, the divider rules.
///
/// Lifted out of settings_screen.dart when the calendar-connection pages needed
/// the same shell. Keeping one copy is the point: a second page that hand-rolls
/// its own row is how two screens in one settings tree start disagreeing about
/// padding, divider insets and where the chevron sits.

List<Widget> dividedRows(List<Widget> rows, {bool inset = false}) => [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) inset ? InsetDivider() : CardDivider(),
        rows[i],
      ],
    ];

/// Chrome shared by every Settings sub-page: the same frosted collapsing
/// header as the root, with a [HeroCard] as the collapsing content and the
/// page's own [title] taking over the pinned bar once that card scrolls away.
class SettingsDetailPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  /// First-frame guess at the hero's height; re-measured immediately.
  final double estimatedHeroHeight;

  const SettingsDetailPage({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
    this.estimatedHeroHeight = 180,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: CollapsingHeaderScreen(
          // No expanded title: the hero card below carries the page's name at
          // rest, and only hands it to the bar as it scrolls out of sight.
          titleRowBuilder: (context, t) => CollapsingScreenTitle(
            title: '',
            collapsedTitle: title,
            t: t,
            expandedAlignment: Alignment.center,
            leading: GlassIconButton(icon: LucideIcons.chevronLeft, onTap: () => Navigator.of(context).pop()),
            leadingWidth: 48,
            trailing: CloseSettingsButton(),
            trailingWidth: 48,
          ),
          estimatedExtraHeight: estimatedHeroHeight,
          extraPadding: const EdgeInsets.symmetric(horizontal: 16),
          extra: HeroCard(icon: icon, title: title, description: description),
          body: ScreenBodyPanel(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
              children: children,
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
    return GlassIconButton(
      icon: LucideIcons.x,
      onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
    );
  }
}

/// The glass "Fertig" pill in the Settings header — a text-labelled sibling of
/// [GlassIconButton], so both controls read as the same material.
class GlassPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const GlassPillButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.bar),
        blurSigma: 16,
        boxShadow: AppShadows.glassButton,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(label, style: AppText.rowTitle),
        ),
      ),
    );
  }
}

/// The masthead every Settings sub-page opens with: an accent glyph, the page's
/// title and one sentence explaining what the page changes. It replaces the
/// nav-bar title on those pages, which is why the pinned row above it is empty
/// until this scrolls away.
///
/// Deliberately *not* a [SectionCard]: it sits on [AppColors.surface], so a
/// white card on white read as a barely-there rectangle whose height jumped
/// with every description's line count. Only the icon carries colour; the
/// title stays ink.
class HeroCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const HeroCard({super.key, required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Horizontal 6 lines the text up with [GroupLabel] and the edge of the
      // cards below, both of which sit inside the same 16pt page gutter.
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 26, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 22),
          Text(title, style: AppText.screenTitle),
          const SizedBox(height: 10),
          Text(description, style: AppText.body.copyWith(color: AppColors.muted)),
        ],
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
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: accent),
              ),
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
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(LucideIcons.chevronRight, size: 16, color: AppColors.mutedLight),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// A labelled block inside a card — caption, optional hint, then the control.
/// Used by the profile form, where each setting needs a name that a plain
/// [SettingsRow] has nowhere to put.
class FieldGroup extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;

  const FieldGroup({super.key, required this.label, this.hint, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.sectionHeading),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: AppText.body.copyWith(color: AppColors.muted)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// [CardDivider] inset from the card's edges — the separator between
/// [FieldGroup]s and member rows, where a full-bleed rule cuts the card in
/// half.
class InsetDivider extends StatelessWidget {
  const InsetDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: CardDivider(),
      );
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

class GroupLabel extends StatelessWidget {
  final String label;

  const GroupLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 9),
      child: Text(label, style: AppText.microLabel.copyWith(letterSpacing: 0.3)),
    );
  }
}
