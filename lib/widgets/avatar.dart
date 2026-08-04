import 'package:flutter/material.dart';
import '../theme/tokens.dart';

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
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: fg,
              ),
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
