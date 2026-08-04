import 'package:flutter/material.dart';
import '../models/who.dart';
import '../theme/tokens.dart';

/// Initials for a name typed into a form.
///
/// Household members carry their own `initials` from the database; this is for
/// the profile draft, which is being edited and so has no stored copy yet. One
/// letter from a single name, first and last from anything longer.
String initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

/// Circular avatar showing a member's initials (or a glyph) in tone colours.
class Avatar extends StatelessWidget {
  final double size;
  final Color bg;
  final Color fg;
  final String? initials;
  final IconData? icon;
  final double fontSize;
  final Border? border;

  const Avatar({
    super.key,
    required this.size,
    required this.bg,
    required this.fg,
    this.initials,
    this.icon,
    this.fontSize = 12,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: border),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: size * 0.44, color: fg)
          : Text(
              initials ?? '',
              // Sized by the caller — an avatar's initials scale with the
              // circle, so this is one of the few sanctioned `fontSize`
              // overrides. Weight and family still come from the scale.
              style: AppText.itemTitle.copyWith(fontSize: fontSize, letterSpacing: 0.2, color: fg),
            ),
    );
  }
}

/// Overlapping avatar stack, e.g. the Board header member stack.
class AvatarStack extends StatelessWidget {
  final List<Widget> avatars;
  final double overlap;
  final double avatarSize;

  const AvatarStack({super.key, required this.avatars, this.overlap = 9, this.avatarSize = 28});

  @override
  Widget build(BuildContext context) {
    if (avatars.isEmpty) return const SizedBox.shrink();
    final step = avatarSize - overlap;
    final width = avatarSize + step * (avatars.length - 1);
    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < avatars.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(color: AppColors.surface, blurRadius: 0, spreadRadius: 2),
                ]),
                child: avatars[i],
              ),
            ),
        ],
      ),
    );
  }
}

/// The avatar side of a [WhoMeta]: one circle for an assignee, "Alle" or
/// "Nur ich", and the overlapping stack of real members for a `custom` item.
///
/// A `custom` badge used to be a single anonymous check glyph, which said an
/// item was restricted but never to whom — the one question a shared-with-three
/// list makes you ask. Each face keeps its own tone, so the stack is scannable
/// at 16px where the label is not.
class WhoAvatars extends StatelessWidget {
  final WhoMeta who;
  final double size;
  final double fontSize;

  /// Past this the circles stop being distinguishable and start pushing the
  /// label out of the row; the label carries the true count anyway.
  static const maxFaces = 3;

  const WhoAvatars({super.key, required this.who, required this.size, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    if (who.stack.isEmpty) {
      return Avatar(size: size, bg: who.bg, fg: who.fg, icon: who.icon, initials: who.initials, fontSize: fontSize);
    }
    return AvatarStack(
      avatarSize: size,
      overlap: size * 0.34,
      avatars: [
        for (final m in who.stack.take(maxFaces))
          Avatar(size: size, bg: m.toneColors.bg, fg: m.toneColors.fg, initials: m.initials, fontSize: fontSize),
      ],
    );
  }
}
